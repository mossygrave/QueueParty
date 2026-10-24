defmodule QueueParty.Rooms do
  @moduledoc "In-memory room and queue state for the first MVP."

  use GenServer

  @topic_prefix "room:"
  @host_grace_ms 30_000
  @empty_room_ms :timer.minutes(15)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def create_room, do: GenServer.call(__MODULE__, :create)

  def get_room(code), do: GenServer.call(__MODULE__, {:get, String.upcase(code)})
  def subscribe(code), do: Phoenix.PubSub.subscribe(QueueParty.PubSub, topic(code))

  def join_room(code, guest_id, host_token, name),
    do: GenServer.call(__MODULE__, {:join, String.upcase(code), guest_id, host_token, name})

  def rename_guest(code, guest_id, name),
    do: GenServer.call(__MODULE__, {:rename_guest, String.upcase(code), guest_id, name})

  def transfer_host(code, host_token, guest_id),
    do: GenServer.call(__MODULE__, {:transfer_host, String.upcase(code), host_token, guest_id})

  def host?(room, guest_id, host_token) do
    (is_binary(guest_id) && room.host_guest_id == guest_id) ||
      (is_nil(room.host_guest_id) && room.host_token == host_token)
  end

  def connected_guests(room) do
    room.participants
    |> Map.values()
    |> Enum.filter(&(map_size(&1.connections) > 0 && &1.id != room.host_guest_id))
    |> Enum.sort_by(& &1.order)
  end

  def add_item(code, youtube_id, submitted_by) do
    result =
      GenServer.call(__MODULE__, {:add_item, String.upcase(code), youtube_id, submitted_by})

    case result do
      {:ok, item} ->
        # Keep HTTP requests outside the room server so playback never waits on metadata.
        Task.Supervisor.start_child(QueueParty.TitleTasks, fn ->
          case QueueParty.YouTube.fetch_title(youtube_id) do
            {:ok, title} -> set_item_title(code, item.id, title)
            :error -> :ok
          end
        end)

      _ ->
        :ok
    end

    result
  end

  @doc false
  def set_item_title(code, item_id, title),
    do: GenServer.call(__MODULE__, {:set_item_title, String.upcase(code), item_id, title})

  def begin_playlist_import(code, host_token),
    do: GenServer.call(__MODULE__, {:begin_playlist_import, String.upcase(code), host_token})

  def complete_playlist_import(code, host_token, marker, playlist),
    do:
      GenServer.call(
        __MODULE__,
        {:complete_playlist_import, String.upcase(code), host_token, marker, playlist}
      )

  def remove_playlist(code, host_token),
    do: GenServer.call(__MODULE__, {:remove_playlist, String.upcase(code), host_token})

  def set_playlist_repeat(code, host_token, repeat?),
    do: GenServer.call(__MODULE__, {:playlist_repeat, String.upcase(code), host_token, repeat?})

  def fail_playlist_item(code, host_token, item_id),
    do:
      GenServer.call(__MODULE__, {:fail_playlist_item, String.upcase(code), host_token, item_id})

  def remove_item(code, item_id),
    do: GenServer.call(__MODULE__, {:remove_item, String.upcase(code), item_id})

  def move_item(code, host_token, item_id, before_id),
    do:
      GenServer.call(
        __MODULE__,
        {:move_item, String.upcase(code), host_token, item_id, before_id}
      )

  def remove_item(code, item_id, host_token),
    do:
      GenServer.call(
        __MODULE__,
        {:host_action, String.upcase(code), host_token, {:remove_item, item_id}}
      )

  def skip(code), do: GenServer.call(__MODULE__, {:skip, String.upcase(code)})

  def skip(code, host_token),
    do: GenServer.call(__MODULE__, {:host_action, String.upcase(code), host_token, :skip})

  def request_skip(code, item_id, guest_id),
    do: GenServer.call(__MODULE__, {:request_skip, String.upcase(code), item_id, guest_id})

  def approve_skip(code, host_token, item_id),
    do: GenServer.call(__MODULE__, {:approve_skip, String.upcase(code), host_token, item_id})

  def set_skip_threshold(code, host_token, threshold),
    do:
      GenServer.call(
        __MODULE__,
        {:set_skip_threshold, String.upcase(code), host_token, threshold}
      )

  def finish(code, item_id),
    do: GenServer.call(__MODULE__, {:finish, String.upcase(code), item_id})

  def finish(code, item_id, host_token),
    do:
      GenServer.call(
        __MODULE__,
        {:host_action, String.upcase(code), host_token, {:finish, item_id}}
      )

  def set_playback_mode(code, host_token, mode),
    do: GenServer.call(__MODULE__, {:set_playback_mode, String.upcase(code), host_token, mode})

  def update_playback(code, host_token, item_id, status, position) do
    GenServer.call(
      __MODULE__,
      {:update_playback, String.upcase(code), host_token, item_id, status, position}
    )
  end

  @doc "Returns the current playhead without exposing a server-specific clock to browsers."
  def playback_snapshot(%{playback: playback}) do
    elapsed =
      if playback.status == "playing", do: (now_ms() - playback.updated_at) / 1000, else: 0

    %{
      item_id: playback.item_id,
      status: playback.status,
      position: playback.position + elapsed,
      revision: playback.revision
    }
  end

  @impl true
  def init(rooms), do: {:ok, rooms}

  @impl true
  def handle_call(:create, _from, rooms) do
    code = unique_code(rooms)

    room = %{
      code: code,
      host_token: token(),
      host_guest_id: nil,
      host_status: "unclaimed",
      host_timer: nil,
      empty_timer: nil,
      participants: %{},
      join_sequence: 0,
      items: [],
      playlist: nil,
      playlist_import: nil,
      now_playing: nil,
      playback_mode: "host_only",
      skip_threshold: 3,
      skip_votes: MapSet.new(),
      playback: %{
        item_id: nil,
        status: "paused",
        position: 0.0,
        updated_at: now_ms(),
        revision: 0
      }
    }

    room = schedule_empty_cleanup(room)
    {:reply, {:ok, room}, Map.put(rooms, code, room)}
  end

  def handle_call({:get, code}, _from, rooms), do: {:reply, Map.get(rooms, code), rooms}

  def handle_call({:join, code, guest_id, host_token, name}, {pid, _}, rooms)
      when is_binary(guest_id) and byte_size(guest_id) > 0 do
    case Map.get(rooms, code) do
      nil ->
        {:reply, {:error, :not_found}, rooms}

      room ->
        cancel_empty_timer(room)
        room = %{room | empty_timer: nil}

        participant =
          Map.get(room.participants, guest_id, %{
            id: guest_id,
            name: name,
            order: room.join_sequence,
            connections: %{}
          })

        participant =
          if map_size(participant.connections) == 0,
            do: %{participant | order: room.join_sequence},
            else: participant

        connections =
          if Map.has_key?(participant.connections, pid),
            do: participant.connections,
            else: Map.put(participant.connections, pid, Process.monitor(pid))

        room = %{
          room
          | participants:
              Map.put(room.participants, guest_id, %{participant | connections: connections}),
            join_sequence: room.join_sequence + 1
        }

        room =
          cond do
            host?(room, guest_id, host_token) ->
              cancel_host_timer(room)
              %{room | host_guest_id: guest_id, host_status: "online", host_timer: nil}

            room.host_status == "waiting" ->
              promote_host(room, guest_id)

            true ->
              room
          end

        save_room(room, rooms)
    end
  end

  def handle_call({:rename_guest, code, guest_id, name}, _from, rooms) do
    case Map.get(rooms, code) do
      %{participants: %{^guest_id => participant}} = room ->
        name = name |> String.trim() |> String.slice(0, 24)
        name = if name == "", do: "Guest", else: name

        room = %{
          room
          | participants: Map.put(room.participants, guest_id, %{participant | name: name})
        }

        save_room(room, rooms)

      _ ->
        {:reply, {:error, :not_found}, rooms}
    end
  end

  def handle_call({:transfer_host, code, host_token, guest_id}, _from, rooms) do
    case Map.get(rooms, code) do
      %{host_token: ^host_token} = room ->
        if Enum.any?(connected_guests(room), &(&1.id == guest_id)),
          do: save_room(promote_host(room, guest_id), rooms),
          else: {:reply, {:error, :guest_unavailable}, rooms}

      nil ->
        {:reply, {:error, :not_found}, rooms}

      _ ->
        {:reply, {:error, :forbidden}, rooms}
    end
  end

  def handle_call({:host_action, code, host_token, action}, from, rooms) do
    case Map.get(rooms, code) do
      %{host_token: ^host_token} ->
        command =
          case action do
            :skip -> {:skip, code}
            {:finish, item_id} -> {:finish, code, item_id}
            {:remove_item, item_id} -> {:remove_item, code, item_id}
          end

        handle_call(command, from, rooms)

      nil ->
        {:reply, {:error, :not_found}, rooms}

      _ ->
        {:reply, {:error, :forbidden}, rooms}
    end
  end

  def handle_call({:add_item, code, youtube_id, submitted_by}, _from, rooms) do
    with %{items: items} = room <- Map.get(rooms, code) do
      item = %{
        id: token(),
        youtube_id: youtube_id,
        submitted_by: submitted_by,
        title: "YouTube video #{youtube_id}",
        inserted_at: DateTime.utc_now()
      }

      room = %{room | items: items ++ [item]}
      room = if is_nil(room.now_playing), do: next_room(room), else: room
      rooms = Map.put(rooms, code, room)
      broadcast(code, {:room_updated, room})
      {:reply, {:ok, item}, rooms}
    else
      nil -> {:reply, {:error, :not_found}, rooms}
    end
  end

  def handle_call({:move_item, code, host_token, item_id, before_id}, _from, rooms) do
    case Map.get(rooms, code) do
      %{host_token: ^host_token, items: items} = room ->
        item = Enum.find(items, &(&1.id == item_id))
        anchor_exists? = is_nil(before_id) || Enum.any?(items, &(&1.id == before_id))

        if item && anchor_exists? && item_id != before_id do
          remaining = Enum.reject(items, &(&1.id == item_id))

          index =
            if is_nil(before_id),
              do: length(remaining),
              else: Enum.find_index(remaining, &(&1.id == before_id))

          save_room(%{room | items: List.insert_at(remaining, index, item)}, rooms)
        else
          {:reply, {:error, :stale_queue}, rooms}
        end

      nil ->
        {:reply, {:error, :not_found}, rooms}

      _ ->
        {:reply, {:error, :forbidden}, rooms}
    end
  end

  def handle_call({:remove_item, code, item_id}, _from, rooms) do
    with %{items: items} = room <- Map.get(rooms, code) do
      room = %{room | items: Enum.reject(items, &(&1.id == item_id))}
      rooms = Map.put(rooms, code, room)
      broadcast(code, {:room_updated, room})
      {:reply, {:ok, room}, rooms}
    else
      nil -> {:reply, {:error, :not_found}, rooms}
    end
  end

  def handle_call({:set_item_title, code, item_id, title}, _from, rooms)
      when is_binary(title) and byte_size(title) in 1..2_000 do
    case Map.get(rooms, code) do
      %{now_playing: %{id: ^item_id} = current} = room ->
        save_room(%{room | now_playing: %{current | title: title}}, rooms)

      %{items: items} = room ->
        if Enum.any?(items, &(&1.id == item_id)) do
          items =
            Enum.map(items, fn item ->
              if item.id == item_id, do: %{item | title: title}, else: item
            end)

          save_room(%{room | items: items}, rooms)
        else
          {:reply, :ignored, rooms}
        end

      _ ->
        {:reply, :ignored, rooms}
    end
  end

  def handle_call({:set_item_title, _, _, _}, _from, rooms), do: {:reply, :ignored, rooms}

  def handle_call({:begin_playlist_import, code, host_token}, _from, rooms) do
    case Map.get(rooms, code) do
      %{host_token: ^host_token} = room ->
        marker = make_ref()
        {:reply, {:ok, marker}, Map.put(rooms, code, %{room | playlist_import: marker})}

      nil ->
        {:reply, {:error, :not_found}, rooms}

      _ ->
        {:reply, {:error, :forbidden}, rooms}
    end
  end

  def handle_call({:complete_playlist_import, code, host_token, marker, data}, _from, rooms) do
    case Map.get(rooms, code) do
      %{host_token: ^host_token, playlist_import: ^marker} = room when not is_nil(marker) ->
        if valid_playlist?(data) do
          repeat? = room.playlist && room.playlist.repeat?
          playlist = Map.merge(data, %{remaining: data.tracks, repeat?: repeat? == true})
          room = %{room | playlist: playlist, playlist_import: nil}
          room = if is_nil(room.now_playing), do: next_room(room), else: room
          save_room(room, rooms)
        else
          {:reply, {:error, :invalid_playlist}, rooms}
        end

      %{host_token: ^host_token} ->
        {:reply, {:error, :stale_import}, rooms}

      nil ->
        {:reply, {:error, :not_found}, rooms}

      _ ->
        {:reply, {:error, :forbidden}, rooms}
    end
  end

  def handle_call({:remove_playlist, code, host_token}, _from, rooms) do
    case Map.get(rooms, code) do
      %{host_token: ^host_token} = room ->
        save_room(%{room | playlist: nil, playlist_import: nil}, rooms)

      nil ->
        {:reply, {:error, :not_found}, rooms}

      _ ->
        {:reply, {:error, :forbidden}, rooms}
    end
  end

  def handle_call({:playlist_repeat, code, host_token, repeat?}, _from, rooms)
      when is_boolean(repeat?) do
    case Map.get(rooms, code) do
      %{host_token: ^host_token, playlist: playlist} = room when not is_nil(playlist) ->
        room = %{room | playlist: %{playlist | repeat?: repeat?}}
        room = if is_nil(room.now_playing), do: next_room(room), else: room
        save_room(room, rooms)

      %{host_token: ^host_token} ->
        {:reply, {:error, :no_playlist}, rooms}

      nil ->
        {:reply, {:error, :not_found}, rooms}

      _ ->
        {:reply, {:error, :forbidden}, rooms}
    end
  end

  def handle_call({:fail_playlist_item, code, host_token, item_id}, _from, rooms) do
    case Map.get(rooms, code) do
      %{host_token: ^host_token, now_playing: %{id: ^item_id, source: :playlist} = item} = room ->
        playlist =
          if room.playlist do
            %{
              room.playlist
              | tracks: Enum.reject(room.playlist.tracks, &(&1.youtube_id == item.youtube_id)),
                remaining:
                  Enum.reject(room.playlist.remaining, &(&1.youtube_id == item.youtube_id))
            }
          end

        advance(%{room | playlist: playlist}, rooms)

      %{host_token: ^host_token} ->
        {:reply, :ignored, rooms}

      nil ->
        {:reply, {:error, :not_found}, rooms}

      _ ->
        {:reply, {:error, :forbidden}, rooms}
    end
  end

  def handle_call({:playlist_repeat, _, _, _}, _from, rooms),
    do: {:reply, {:error, :invalid_repeat}, rooms}

  def handle_call({:skip, code}, _from, rooms) do
    case Map.get(rooms, code) do
      nil -> {:reply, {:error, :not_found}, rooms}
      room -> advance(room, rooms)
    end
  end

  def handle_call({:finish, code, item_id}, _from, rooms) do
    case Map.get(rooms, code) do
      %{now_playing: %{id: ^item_id}} = room -> advance(room, rooms)
      nil -> {:reply, {:error, :not_found}, rooms}
      room -> {:reply, {:ok, room}, rooms}
    end
  end

  def handle_call({:request_skip, code, item_id, guest_id}, _from, rooms)
      when is_binary(guest_id) and byte_size(guest_id) > 0 do
    case Map.get(rooms, code) do
      %{now_playing: %{id: ^item_id}} = room ->
        room = %{room | skip_votes: MapSet.put(room.skip_votes, guest_id)}
        maybe_skip(room, rooms)

      nil ->
        {:reply, {:error, :not_found}, rooms}

      _ ->
        {:reply, {:error, :stale_item}, rooms}
    end
  end

  def handle_call({:request_skip, _, _, _}, _from, rooms),
    do: {:reply, {:error, :invalid_guest}, rooms}

  def handle_call({:approve_skip, code, host_token, item_id}, _from, rooms) do
    case Map.get(rooms, code) do
      %{host_token: ^host_token, now_playing: %{id: ^item_id}} = room -> advance(room, rooms)
      %{host_token: ^host_token} -> {:reply, {:error, :stale_item}, rooms}
      nil -> {:reply, {:error, :not_found}, rooms}
      _ -> {:reply, {:error, :forbidden}, rooms}
    end
  end

  def handle_call({:set_skip_threshold, code, host_token, threshold}, _from, rooms)
      when is_integer(threshold) and threshold in 1..100 do
    case Map.get(rooms, code) do
      %{host_token: ^host_token} = room ->
        maybe_skip(%{room | skip_threshold: threshold}, rooms)

      nil ->
        {:reply, {:error, :not_found}, rooms}

      _ ->
        {:reply, {:error, :forbidden}, rooms}
    end
  end

  def handle_call({:set_skip_threshold, _, _, _}, _from, rooms),
    do: {:reply, {:error, :invalid_threshold}, rooms}

  def handle_call({:set_playback_mode, code, host_token, mode}, _from, rooms)
      when mode in ["host_only", "everyone"] do
    case Map.get(rooms, code) do
      %{host_token: ^host_token} = room ->
        room = %{room | playback_mode: mode}
        broadcast(code, {:room_updated, room})
        {:reply, {:ok, room}, Map.put(rooms, code, room)}

      nil ->
        {:reply, {:error, :not_found}, rooms}

      _ ->
        {:reply, {:error, :forbidden}, rooms}
    end
  end

  def handle_call({:set_playback_mode, _, _, _}, _from, rooms),
    do: {:reply, {:error, :invalid_mode}, rooms}

  def handle_call({:update_playback, code, host_token, item_id, status, position}, _from, rooms)
      when status in ["playing", "paused", "buffering"] and is_number(position) and
             position >= 0 and position <= 604_800 do
    case Map.get(rooms, code) do
      %{host_token: ^host_token, now_playing: %{id: ^item_id}} = room ->
        playback = %{
          item_id: item_id,
          status: status,
          position: position,
          updated_at: now_ms(),
          revision: room.playback.revision + 1
        }

        room = %{room | playback: playback}
        broadcast(code, {:playback_updated, playback_snapshot(room)})
        {:reply, :ok, Map.put(rooms, code, room)}

      %{host_token: ^host_token} ->
        {:reply, {:error, :stale_item}, rooms}

      nil ->
        {:reply, {:error, :not_found}, rooms}

      _ ->
        {:reply, {:error, :forbidden}, rooms}
    end
  end

  def handle_call({:update_playback, _, _, _, _, _}, _from, rooms),
    do: {:reply, {:error, :invalid_playback}, rooms}

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, rooms) do
    rooms =
      Map.new(rooms, fn {code, room} ->
        case Enum.find(room.participants, fn {_id, participant} ->
               Map.get(participant.connections, pid) == ref
             end) do
          nil ->
            {code, room}

          {guest_id, participant} ->
            participant = %{participant | connections: Map.delete(participant.connections, pid)}
            room = %{room | participants: Map.put(room.participants, guest_id, participant)}

            room =
              if guest_id == room.host_guest_id && map_size(participant.connections) == 0 do
                marker = make_ref()

                timer =
                  Process.send_after(self(), {:host_grace_expired, code, marker}, @host_grace_ms)

                %{room | host_status: "reconnecting", host_timer: {timer, marker}}
              else
                room
              end

            room = schedule_empty_cleanup(room)
            broadcast(code, {:room_updated, room})
            {code, room}
        end
      end)

    {:noreply, rooms}
  end

  def handle_info({:host_grace_expired, code, marker}, rooms) do
    case Map.get(rooms, code) do
      %{host_timer: {_, ^marker}, host_status: "reconnecting"} = room ->
        room =
          case connected_guests(room) do
            [next | _] -> promote_host(room, next.id)
            [] -> %{room | host_status: "waiting", host_timer: nil}
          end

        broadcast(code, {:room_updated, room})
        {:noreply, Map.put(rooms, code, room)}

      _ ->
        {:noreply, rooms}
    end
  end

  def handle_info({:empty_room_expired, code, marker}, rooms) do
    case Map.get(rooms, code) do
      %{empty_timer: {_, ^marker}} = room ->
        if empty_room?(room) do
          cancel_empty_timer(room)
          cancel_host_timer(room)
          {:noreply, Map.delete(rooms, code)}
        else
          {:noreply, rooms}
        end

      _ ->
        {:noreply, rooms}
    end
  end

  defp empty_room?(room),
    do:
      Enum.all?(room.participants, fn {_id, participant} ->
        map_size(participant.connections) == 0
      end)

  defp schedule_empty_cleanup(room) do
    if is_nil(room.empty_timer) && empty_room?(room) do
      marker = make_ref()
      timer = Process.send_after(self(), {:empty_room_expired, room.code, marker}, @empty_room_ms)
      %{room | empty_timer: {timer, marker}}
    else
      room
    end
  end

  defp cancel_empty_timer(%{empty_timer: {timer, _}}), do: Process.cancel_timer(timer)
  defp cancel_empty_timer(_room), do: :ok

  defp cancel_host_timer(%{host_timer: {timer, _}}), do: Process.cancel_timer(timer)
  defp cancel_host_timer(_room), do: :ok

  defp promote_host(room, guest_id) do
    cancel_host_timer(room)
    %{room | host_guest_id: guest_id, host_token: token(), host_status: "online", host_timer: nil}
  end

  defp save_room(room, rooms) do
    broadcast(room.code, {:room_updated, room})
    {:reply, {:ok, room}, Map.put(rooms, room.code, room)}
  end

  defp advance(room, rooms) do
    room |> next_room() |> save_room(rooms)
  end

  defp next_room(room) do
    {next, rest, playlist} =
      case room.items do
        [item | rest] ->
          {item, rest, room.playlist}

        [] ->
          {item, playlist} = next_playlist_item(room.playlist)
          {item, [], playlist}
      end

    playback = %{
      item_id: next && next.id,
      status: if(next, do: "playing", else: "paused"),
      position: 0.0,
      updated_at: now_ms(),
      revision: room.playback.revision + 1
    }

    %{
      room
      | items: rest,
        playlist: playlist,
        now_playing: next,
        playback: playback,
        skip_votes: MapSet.new()
    }
  end

  defp next_playlist_item(nil), do: {nil, nil}

  defp next_playlist_item(playlist) do
    available =
      if playlist.remaining == [] && playlist.repeat?,
        do: playlist.tracks,
        else: playlist.remaining

    case available do
      [track | rest] ->
        item =
          Map.merge(track, %{
            id: token(),
            source: :playlist,
            submitted_by: "Host playlist",
            inserted_at: DateTime.utc_now()
          })

        {item, %{playlist | remaining: rest}}

      [] ->
        {nil, playlist}
    end
  end

  defp valid_playlist?(%{id: id, title: title, url: url, tracks: tracks})
       when is_binary(id) and is_binary(title) and is_binary(url) and is_list(tracks) do
    length(tracks) in 1..200 &&
      Enum.all?(tracks, fn
        %{youtube_id: video_id, title: name} when is_binary(video_id) and is_binary(name) ->
          Regex.match?(~r/\A[A-Za-z0-9_-]{11}\z/, video_id) && String.trim(name) != ""

        _ ->
          false
      end)
  end

  defp valid_playlist?(_), do: false

  defp maybe_skip(room, rooms) do
    if room.now_playing && MapSet.size(room.skip_votes) >= room.skip_threshold do
      advance(room, rooms)
    else
      broadcast(room.code, {:room_updated, room})
      {:reply, {:ok, room}, Map.put(rooms, room.code, room)}
    end
  end

  defp broadcast(code, message),
    do: Phoenix.PubSub.broadcast(QueueParty.PubSub, topic(code), message)

  defp topic(code), do: @topic_prefix <> String.upcase(code)
  defp token, do: :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  defp now_ms, do: System.monotonic_time(:millisecond)

  defp unique_code(rooms) do
    code = :crypto.strong_rand_bytes(3) |> Base.encode32(case: :upper, padding: false)
    if Map.has_key?(rooms, code), do: unique_code(rooms), else: code
  end
end
