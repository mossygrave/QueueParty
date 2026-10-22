defmodule QueueParty.Rooms do
  @moduledoc "In-memory room and queue state for the first MVP."

  use GenServer

  @topic_prefix "room:"

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def create_room, do: GenServer.call(__MODULE__, :create)

  def get_room(code), do: GenServer.call(__MODULE__, {:get, String.upcase(code)})
  def subscribe(code), do: Phoenix.PubSub.subscribe(QueueParty.PubSub, topic(code))

  def add_item(code, youtube_id, submitted_by) do
    GenServer.call(__MODULE__, {:add_item, String.upcase(code), youtube_id, submitted_by})
  end

  def remove_item(code, item_id),
    do: GenServer.call(__MODULE__, {:remove_item, String.upcase(code), item_id})

  def skip(code), do: GenServer.call(__MODULE__, {:skip, String.upcase(code)})

  def finish(code, item_id),
    do: GenServer.call(__MODULE__, {:finish, String.upcase(code), item_id})

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
      items: [],
      now_playing: nil,
      playback_mode: "host_only",
      playback: %{
        item_id: nil,
        status: "paused",
        position: 0.0,
        updated_at: now_ms(),
        revision: 0
      }
    }

    {:reply, {:ok, room}, Map.put(rooms, code, room)}
  end

  def handle_call({:get, code}, _from, rooms), do: {:reply, Map.get(rooms, code), rooms}

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
      rooms = Map.put(rooms, code, room)
      broadcast(code, {:room_updated, room})
      {:reply, {:ok, item}, rooms}
    else
      nil -> {:reply, {:error, :not_found}, rooms}
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

  defp advance(room, rooms) do
    {next, rest} =
      case room.items do
        [item | rest] -> {item, rest}
        [] -> {nil, []}
      end

    playback = %{
      item_id: next && next.id,
      status: if(next, do: "playing", else: "paused"),
      position: 0.0,
      updated_at: now_ms(),
      revision: room.playback.revision + 1
    }

    room = %{room | items: rest, now_playing: next, playback: playback}
    broadcast(room.code, {:room_updated, room})
    {:reply, {:ok, room}, Map.put(rooms, room.code, room)}
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
