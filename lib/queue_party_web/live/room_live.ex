defmodule QueuePartyWeb.RoomLive do
  use QueuePartyWeb, :live_view

  alias QueueParty.{Rooms, YouTube}
  alias QueueParty.YouTubePlaylist

  @impl true
  def mount(%{"code" => code} = params, session, socket) do
    code = String.upcase(code)
    name = "Guest #{Enum.random(100..999)}"

    result =
      if connected?(socket) do
        Rooms.subscribe(code)
        Rooms.join_room(code, session["guest_id"], params["host"], name)
      else
        case Rooms.get_room(code) do
          nil -> {:error, :not_found}
          room -> {:ok, room}
        end
      end

    case result do
      {:error, :not_found} ->
        {:ok, socket |> put_flash(:error, "That room no longer exists.") |> redirect(to: ~p"/")}

      {:ok, room} ->
        {:ok,
         socket
         |> assign(:code, code)
         |> assign(:host?, params["host"] == room.host_token)
         |> assign(:host_token, params["host"])
         |> assign(:guest_id, session["guest_id"])
         |> assign(:video_form, to_form(%{"url" => ""}))
         |> assign(:name_form, to_form(%{"name" => name}))
         |> assign(:error, nil)
         |> assign(:host_menu_open?, false)
         |> assign(:playlist_form, to_form(%{"url" => ""}))
         |> assign(:playlist_job, nil)
         |> assign(:playlist_error, nil)
         |> assign(
           :playlist_configured?,
           is_binary(Application.get_env(:queue_party, :youtube_api_key)) &&
             String.trim(Application.get_env(:queue_party, :youtube_api_key)) != ""
         )
         |> assign_room(room)}
    end
  end

  @impl true
  def handle_event("toggle_host_menu", _params, socket) do
    {:noreply,
     assign(socket, :host_menu_open?, socket.assigns.host? && !socket.assigns.host_menu_open?)}
  end

  def handle_event("close_host_menu", _params, socket) do
    {:noreply, assign(socket, :host_menu_open?, false)}
  end

  def handle_event("load_playlist", %{"url" => url}, socket) do
    with true <- socket.assigns.host?,
         {:ok, _id} <- YouTubePlaylist.playlist_id(url),
         {:ok, marker} <-
           Rooms.begin_playlist_import(socket.assigns.code, socket.assigns.host_token) do
      job = {:playlist_import, marker, socket.assigns.host_token}

      {:noreply,
       socket
       |> assign(playlist_job: job, playlist_error: nil, playlist_form: to_form(%{"url" => url}))
       |> start_async(job, fn -> YouTubePlaylist.fetch(url) end)}
    else
      _ ->
        {:noreply,
         assign(
           socket,
           :playlist_error,
           "Only the host can load a valid YouTube playlist URL. YouTube Mix links are not supported."
         )}
    end
  end

  def handle_event("remove_playlist", _params, socket) do
    case Rooms.remove_playlist(socket.assigns.code, socket.assigns.host_token) do
      {:ok, _} -> {:noreply, assign(socket, playlist_job: nil, playlist_error: nil)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("playlist_repeat", %{"repeat" => repeat}, socket) do
    if socket.assigns.host? && repeat in ["true", "false"] do
      Rooms.set_playlist_repeat(socket.assigns.code, socket.assigns.host_token, repeat == "true")
    end

    {:noreply, socket}
  end

  def handle_event("submit_video", %{"url" => url}, socket) do
    case YouTube.video_id(url) do
      {:ok, id} ->
        case Rooms.add_item(socket.assigns.code, id, socket.assigns.name_form[:name].value) do
          {:ok, _item} ->
            socket =
              socket
              |> assign(video_form: to_form(%{"url" => ""}), error: nil)
              |> push_event("video_added", %{})

            {:noreply, socket}

          {:error, _} ->
            {:noreply, assign(socket, :error, "This room is no longer available.")}
        end

      :error ->
        {:noreply,
         assign(socket,
           video_form: to_form(%{"url" => url}),
           error: "Paste a valid YouTube link."
         )}
    end
  end

  def handle_event("set_name", %{"name" => name}, socket) do
    name = name |> String.trim() |> String.slice(0, 24)
    name = if name == "", do: "Guest", else: name
    Rooms.rename_guest(socket.assigns.code, socket.assigns.guest_id, name)
    {:noreply, assign(socket, :name_form, to_form(%{"name" => name}))}
  end

  def handle_event("transfer_host", %{"guest_id" => guest_id}, socket) do
    result = Rooms.transfer_host(socket.assigns.code, socket.assigns.host_token, guest_id)

    socket =
      case result do
        {:ok, room} ->
          assign_room(socket, room)

        _ ->
          put_flash(
            socket,
            :error,
            "That guest is no longer available. Choose a connected guest."
          )
      end

    {:noreply, socket}
  end

  def handle_event("remove", %{"id" => id}, socket) do
    if socket.assigns.host?,
      do: Rooms.remove_item(socket.assigns.code, id, socket.assigns.host_token)

    {:noreply, socket}
  end

  def handle_event("move_queue_item", %{"id" => id, "before_id" => before_id}, socket) do
    case Rooms.move_item(socket.assigns.code, socket.assigns.host_token, id, before_id) do
      {:ok, room} ->
        {:noreply, socket |> assign_room(room) |> push_event("queue_reordered", %{id: id})}

      {:error, :stale_queue} ->
        {:noreply,
         put_flash(socket, :error, "The queue changed. Please try moving that song again.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("skip", _params, socket) do
    if socket.assigns.host?, do: Rooms.skip(socket.assigns.code, socket.assigns.host_token)
    {:noreply, assign(socket, :error, nil)}
  end

  def handle_event("request_skip", %{"item_id" => item_id}, socket) do
    unless socket.assigns.host? do
      Rooms.request_skip(socket.assigns.code, item_id, socket.assigns.guest_id)
    end

    {:noreply, socket}
  end

  def handle_event("approve_skip", %{"item_id" => item_id}, socket) do
    if socket.assigns.host? do
      Rooms.approve_skip(socket.assigns.code, socket.assigns.host_token, item_id)
    end

    {:noreply, socket}
  end

  def handle_event("set_skip_threshold", %{"skip_threshold" => value}, socket) do
    result =
      with true <- socket.assigns.host?,
           true <- is_binary(value),
           {threshold, ""} <- Integer.parse(value),
           {:ok, _room} <-
             Rooms.set_skip_threshold(socket.assigns.code, socket.assigns.host_token, threshold) do
        :ok
      else
        _ -> :error
      end

    socket =
      if result == :error && socket.assigns.host?,
        do: put_flash(socket, :error, "Choose a whole number from 1 to 100."),
        else: socket

    {:noreply, socket}
  end

  def handle_event("video_ended", %{"item_id" => item_id}, socket) do
    if socket.assigns.host?,
      do: Rooms.finish(socket.assigns.code, item_id, socket.assigns.host_token)

    {:noreply, socket}
  end

  def handle_event("set_playback_mode", %{"playback_mode" => mode}, socket) do
    if socket.assigns.host? do
      Rooms.set_playback_mode(socket.assigns.code, socket.assigns.host_token, mode)
    end

    {:noreply, socket}
  end

  def handle_event(
        "playback_update",
        %{"item_id" => item_id, "status" => status, "position" => position},
        socket
      ) do
    if socket.assigns.host? do
      Rooms.update_playback(
        socket.assigns.code,
        socket.assigns.host_token,
        item_id,
        status,
        position
      )
    end

    {:noreply, socket}
  end

  def handle_event("request_playback", _params, socket) do
    room = Rooms.get_room(socket.assigns.code)
    {:reply, %{playback: room && Rooms.playback_snapshot(room)}, socket}
  end

  def handle_event("player_error", %{"item_id" => item_id, "code" => code}, socket)
      when code in [2, 100, 101, 150] do
    if socket.assigns.host? do
      Rooms.fail_playlist_item(socket.assigns.code, socket.assigns.host_token, item_id)
    end

    {:noreply,
     assign(
       socket,
       :error,
       "YouTube couldn’t play this video. Unavailable playlist entries are skipped automatically."
     )}
  end

  def handle_event("player_error", _params, socket) do
    {:noreply,
     assign(
       socket,
       :error,
       "YouTube couldn’t play this video here. Try the player again or skip it."
     )}
  end

  def handle_event("autoplay_blocked", _params, socket) do
    {:noreply,
     assign(socket, :error, "Tap Play in the YouTube player to allow playback on this device.")}
  end

  @impl true
  def handle_info({:room_updated, room}, socket), do: {:noreply, assign_room(socket, room)}

  def handle_info({:playback_updated, playback}, socket),
    do: {:noreply, push_event(socket, "room_playback", playback)}

  @impl true
  def handle_async({:playlist_import, marker, token} = job, {:ok, result}, socket) do
    if socket.assigns.playlist_job == job do
      result =
        case result do
          {:ok, playlist} ->
            Rooms.complete_playlist_import(socket.assigns.code, token, marker, playlist)

          error ->
            error
        end

      error =
        case result do
          {:ok, _room} -> nil
          {:error, reason} -> playlist_error(reason)
        end

      {:noreply, assign(socket, playlist_job: nil, playlist_error: error)}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:playlist_import, _, _} = job, {:exit, _reason}, socket) do
    if socket.assigns.playlist_job == job,
      do:
        {:noreply,
         assign(socket,
           playlist_job: nil,
           playlist_error: "Playlist import failed. Please try again."
         )},
      else: {:noreply, socket}
  end

  defp playlist_error(:missing_api_key),
    do:
      "Playlist imports need YOUTUBE_API_KEY configured on the server. Individual video links still work."

  defp playlist_error(:not_public),
    do: "That playlist is missing or isn’t public. Choose a public playlist."

  defp playlist_error(:empty), do: "That playlist has no available videos."
  defp playlist_error(:too_large), do: "Choose a playlist with no more than 200 entries."

  defp playlist_error(:api_access),
    do:
      "YouTube denied the import. Check the server API key, API restrictions, and available quota."

  defp playlist_error(:stale_import), do: "This import was superseded by another playlist change."

  defp playlist_error(:forbidden),
    do: "Host controls changed during the import. The current host can try again."

  defp playlist_error(_),
    do:
      "Couldn’t retrieve that playlist. Your existing playlist and requests are unchanged. Try again."

  defp assign_room(socket, room) do
    items =
      Enum.with_index(room.items, 1)
      |> Enum.map(fn {item, position} -> Map.put(item, :position, position) end)

    host? = Rooms.host?(room, socket.assigns.guest_id, socket.assigns.host_token)
    candidates = Rooms.connected_guests(room)
    participant = Map.get(room.participants, socket.assigns.guest_id)
    host = Map.get(room.participants, room.host_guest_id)

    participants =
      room.participants
      |> Map.values()
      |> Enum.filter(&(map_size(&1.connections) > 0))
      |> Enum.sort_by(&{if(&1.id == room.host_guest_id, do: 0, else: 1), &1.order})
      |> Enum.map(fn person ->
        %{
          id: person.id,
          name: person.name,
          host?: person.id == room.host_guest_id,
          self?: person.id == socket.assigns.guest_id
        }
      end)

    upcoming =
      if room.playlist do
        tracks =
          if room.playlist.remaining == [] && room.playlist.repeat?,
            do: room.playlist.tracks,
            else: room.playlist.remaining

        tracks
        |> Enum.take(10)
        |> Enum.with_index(1)
        |> Enum.map(fn {track, index} -> Map.put(track, :id, "#{room.playlist.id}-#{index}") end)
      else
        []
      end

    socket
    |> assign(:host?, host?)
    |> assign(:host_menu_open?, host? && socket.assigns.host_menu_open?)
    |> assign(:host_token, if(host?, do: room.host_token))
    |> assign(:host_status, room.host_status)
    |> assign(:host_name, if(host, do: host.name, else: "Host"))
    |> assign(
      :transfer_options,
      Enum.map(candidates, &{"#{&1.name} · guest #{&1.order + 1}", &1.id})
    )
    |> assign(:transfer_form, to_form(%{"guest_id" => ""}))
    |> assign(
      :name_form,
      if(participant, do: to_form(%{"name" => participant.name}), else: socket.assigns.name_form)
    )
    |> assign(:now_playing, room.now_playing)
    |> assign(:playback_mode, room.playback_mode)
    |> assign(:skip_threshold, room.skip_threshold)
    |> assign(:skip_vote_count, MapSet.size(room.skip_votes))
    |> assign(:skip_voted?, MapSet.member?(room.skip_votes, socket.assigns.guest_id))
    |> assign(:skip_form, to_form(%{"skip_threshold" => to_string(room.skip_threshold)}))
    |> assign(:playback, Rooms.playback_snapshot(room))
    |> assign(:settings_form, to_form(%{"playback_mode" => room.playback_mode}))
    |> assign(:queue_count, length(items))
    |> assign(:participant_count, length(participants))
    |> assign(:playlist, room.playlist)
    |> assign(:playlist_preview_count, length(upcoming))
    |> assign(
      :playlist_repeat_form,
      to_form(%{"repeat" => room.playlist && room.playlist.repeat? == true})
    )
    |> stream(:items, items, reset: true)
    |> stream(:playlist_items, upcoming, reset: true)
    |> stream(:participants, participants, reset: true)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="app-shell room-shell">
        <header class="topbar">
          <.link navigate={~p"/"} class="brand">Queue<span>Party</span></.link>
          <div class="room-share">
            <div class="room-badge">ROOM <strong>{@code}</strong></div>
            <button
              id="copy-room-link"
              phx-hook="CopyRoomLink"
              data-path={~p"/room/#{@code}"}
              class="copy-link"
            >Copy invite</button>
            <button
              :if={@host?}
              id="toggle-host-controls"
              type="button"
              phx-click="toggle_host_menu"
              aria-expanded={to_string(@host_menu_open?)}
              aria-controls="host-controls"
              class="host-controls-toggle"
            >
              Host controls <span aria-hidden="true">{if @host_menu_open?, do: "−", else: "+"}</span>
            </button>
          </div>
        </header>

        <div id="host-status" class="host-status" role="status" data-status={@host_status}>
          <%= case @host_status do %>
            <% "reconnecting" -> %>
              Host disconnected. Waiting up to 30 seconds for them to reconnect before passing control to the longest-connected guest.
            <% "waiting" -> %>
              Waiting for a host. The previous host can reconnect, or the next guest to join will take over.
            <% _ -> %>
              {if @host?, do: "You’re the host", else: "Host: #{@host_name}"}
          <% end %>
        </div>

        <section
          :if={@host?}
          id="host-controls"
          class="host-controls"
          aria-labelledby="host-controls-title"
          hidden={!@host_menu_open?}
          phx-window-keydown={
            if(@host_menu_open?,
              do: JS.push("close_host_menu") |> JS.focus(to: "#toggle-host-controls")
            )
          }
          phx-key="Escape"
        >
          <div class="host-controls-heading">
            <div>
              <h2 id="host-controls-title">Your room, your rules.</h2>
              <p>Adjust the settings, then get back to the music.</p>
            </div>
            <button
              id="close-host-controls"
              type="button"
              phx-click={JS.push("close_host_menu") |> JS.focus(to: "#toggle-host-controls")}
              class="host-controls-close"
            >
              Close <span aria-hidden="true">×</span>
            </button>
          </div>
          <div class="host-controls-grid">
            <section id="room-settings" class="room-settings" aria-label="Room settings">
              <div>
                <div class="eyebrow">ROOM SETTINGS</div>
                <p>Choose where everyone listens. You stay in control of playback.</p>
              </div>
              <.form
                for={@settings_form}
                id="playback-settings"
                phx-change="set_playback_mode"
                phx-submit="set_playback_mode"
              >
                <.input
                  field={@settings_form[:playback_mode]}
                  id="playback-mode"
                  type="select"
                  label="Play music on"
                  class="playback-select"
                  options={[{"Host device only", "host_only"}, {"Every device", "everyone"}]}
                />
              </.form>
              <.form for={@skip_form} id="skip-settings" phx-submit="set_skip_threshold">
                <.input
                  field={@skip_form[:skip_threshold]}
                  id="skip-threshold"
                  type="number"
                  label="Votes needed to skip"
                  min="1"
                  max="100"
                  step="1"
                  required
                  class="playback-select"
                />
                <button id="save-skip-threshold" type="submit" class="settings-save">Save</button>
                <p>Default: 3 votes. Lowering the limit can skip the current song immediately.</p>
              </.form>
              <.form for={@transfer_form} id="transfer-host-form" phx-submit="transfer_host">
                <.input
                  field={@transfer_form[:guest_id]}
                  id="transfer-host-guest"
                  type="select"
                  label="Transfer host"
                  prompt="Choose a connected guest"
                  options={@transfer_options}
                  required
                  class="playback-select"
                />
                <button
                  id="transfer-host"
                  type="submit"
                  class="settings-save"
                  disabled={@transfer_options == []}
                  data-confirm="Transfer host controls? You will become a guest."
                >
                  Pass host controls
                </button>
                <p>
                  Your queue and settings stay the same. The new host keeps control when you return.
                </p>
              </.form>
            </section>

            <section
              id="playlist-settings"
              class="playlist-settings"
              aria-label="Background playlist settings"
            >
              <div class="eyebrow">BACKGROUND PLAYLIST</div>
              <p>
                Play next requests take priority after the current song. The playlist then resumes in order.
              </p>
              <p :if={!@playlist_configured?} id="playlist-api-warning">
                Set YOUTUBE_API_KEY on the server to enable playlist imports. Individual links still work.
              </p>
              <.form
                for={@playlist_form}
                id="playlist-form"
                phx-submit="load_playlist"
                class="playlist-form"
              >
                <.input
                  field={@playlist_form[:url]}
                  id="playlist-url"
                  type="url"
                  label="Public YouTube playlist URL"
                  placeholder="https://www.youtube.com/playlist?list=…"
                  required
                  class="playlist-url-input"
                />
                <button
                  id="load-playlist"
                  type="submit"
                  disabled={!is_nil(@playlist_job)}
                  class="settings-save"
                >
                  {if @playlist_job, do: "Loading playlist…", else: "Load / replace playlist"}
                </button>
              </.form>
              <.form
                :if={@playlist}
                for={@playlist_repeat_form}
                id="playlist-repeat-form"
                phx-change="playlist_repeat"
              >
                <.input
                  field={@playlist_repeat_form[:repeat]}
                  id="playlist-repeat"
                  type="checkbox"
                  label="Repeat playlist"
                />
              </.form>
              <button
                :if={@playlist || @playlist_job}
                id="remove-playlist"
                type="button"
                phx-click="remove_playlist"
                class="settings-save"
              >Remove playlist</button>
              <p :if={@playlist_job} id="playlist-loading" role="status">
                Importing in the background. Playback continues.
              </p>
              <p :if={@playlist_error} id="playlist-error" class="error-message" role="alert">
                {@playlist_error}
              </p>
            </section>
          </div>
        </section>

        <main class="room-layout">
          <section class="player-panel">
            <div class="eyebrow">NOW PLAYING · {if @host?, do: "HOST", else: "GUEST"}</div>
            <p id="playback-mode-label" class="playback-mode-label">
              {if @playback_mode == "everyone",
                do: "Listening on every device",
                else: "Listening on the host’s device"}
            </p>
            <div
              :if={@now_playing && (@host? || @playback_mode == "everyone")}
              id="youtube-player"
              class="player-frame"
              phx-hook="YouTubePlayer"
              phx-update="ignore"
              data-video-id={@now_playing.youtube_id}
              data-item-id={@now_playing.id}
              data-host={to_string(@host?)}
              data-playback-status={@playback.status}
              data-playback-position={@playback.position}
              data-playback-revision={@playback.revision}
            >
            </div>
            <div :if={!@host? && @now_playing && @playback_mode == "host_only"} class="guest-playing">
              <img
                src={"https://img.youtube.com/vi/#{@now_playing.youtube_id}/hqdefault.jpg"}
                alt="Current video thumbnail"
              />
              <p>Playing on the host’s device</p>
            </div>
            <div
              :if={!@host? && @now_playing && @playback_mode == "everyone"}
              id="device-playback"
              class="device-playback"
            >
              <button
                id="enable-device-audio"
                type="button"
                phx-click={JS.dispatch("queueparty:enable-audio", to: "#youtube-player")}
                class="play-first"
                aria-describedby="device-playback-hint"
              >Play on this device</button>
              <p id="device-playback-hint">
                If you don’t hear audio, tap Play here or in the YouTube player. The host controls the song; your volume is local.
              </p>
            </div>
            <div :if={!@now_playing} class="empty-player">
              <div class="play-orb" aria-hidden="true">▶</div>
              <h1>Drop a song into the room</h1>
              <p>
                Add a video and playback starts automatically. Your browser may ask you to tap Play.
              </p>
            </div>
            <h2 :if={@now_playing} id="now-playing-title" class="now-playing-title">
              {@now_playing.title}
            </h2>
            <div :if={@now_playing} id="now-playing" class="player-meta">
              <div><span class="live-dot"></span>Added by {@now_playing.submitted_by}</div>
              <button :if={@host?} id="skip-video" phx-click="skip" class="text-button">Skip to next →</button>
            </div>
            <section
              :if={@now_playing}
              id="skip-requests"
              class="skip-requests"
              aria-label="Skip requests"
            >
              <p id="skip-vote-count" role="status">
                Skip requests: {@skip_vote_count} / {@skip_threshold}
              </p>
              <button
                :if={!@host?}
                id="request-skip"
                type="button"
                phx-click="request_skip"
                phx-value-item_id={@now_playing.id}
                disabled={@skip_voted?}
                class="play-first"
              >
                {if @skip_voted?, do: "Skip requested", else: "Request skip"}
              </button>
              <button
                :if={@host? && @skip_vote_count > 0}
                id="approve-skip"
                type="button"
                phx-click="approve_skip"
                phx-value-item_id={@now_playing.id}
                class="play-first"
              >
                Approve skip
              </button>
              <p class="skip-hint">
                The host can approve early. At {@skip_threshold} votes, the song skips automatically.
              </p>
            </section>
          </section>

          <aside class="queue-panel">
            <div class="queue-heading">
              <div>
                <div class="eyebrow">PLAY NEXT</div><h2>{@queue_count} videos</h2>
              </div>
              <span class="people-pill">● live room</span>
            </div>
            <div :if={@queue_count == 0} id="queue-empty" class="queue-empty">
              No individual requests.<br /><span>Add a song to play after the current video.</span>
            </div>
            <p :if={@host?} id="queue-reorder-hint" class="queue-reorder-hint">
              Drag the grip to reorder. You can also focus it and use the ↑ / ↓ keys.
            </p>
            <div id="queue-reorder-control" phx-hook="QueueReorder" phx-update="ignore">
              <div class="queue-drop-marker" hidden></div>
              <p class="queue-reorder-status" role="status" aria-live="polite"></p>
            </div>
            <ol
              id="queue"
              class="queue-list"
              phx-update="stream"
              data-reorder-enabled={to_string(@host?)}
            >
              <li
                :for={{dom_id, item} <- @streams.items}
                id={dom_id}
                class="queue-item"
                data-item-id={item.id}
              >
                <button
                  :if={@host?}
                  type="button"
                  id={"reorder-#{item.id}"}
                  class="queue-drag-handle"
                  aria-label={"Reorder #{item.title}"}
                  aria-describedby="queue-reorder-hint"
                  title="Drag to reorder, or use the up and down arrow keys"
                >
                  <.icon name="hero-bars-3" class="queue-grip-icon" />
                </button>
                <span class="queue-number">{item.position}</span>
                <img src={"https://img.youtube.com/vi/#{item.youtube_id}/mqdefault.jpg"} alt="" />
                <div class="queue-copy">
                  <strong title={item.title}>{item.title}</strong><small>added by {item.submitted_by}</small>
                </div>
                <button
                  :if={@host?}
                  id={"remove-#{item.id}"}
                  phx-click="remove"
                  phx-value-id={item.id}
                  class="remove-button"
                  aria-label="Remove video"
                >×</button>
              </li>
            </ol>
            <section
              id="background-playlist"
              class="background-playlist"
              aria-label="Background playlist"
            >
              <div class="eyebrow">HOST PLAYLIST</div>
              <%= if @playlist do %>
                <h2 id="playlist-title">{@playlist.title}</h2>
                <p id="playlist-status" role="status">
                  {length(@playlist.tracks)} available videos · {if @playlist.repeat?,
                    do: "Repeat on",
                    else: "Repeat off"}
                </p>
                <p :if={@playlist_preview_count == 0} id="playlist-exhausted">
                  No more playlist tracks. Add requests, load another playlist, or enable repeat.
                </p>
                <p :if={@playlist_preview_count > 0}>Next playlist tracks (up to 10):</p>
              <% else %>
                <p id="no-playlist">The host can load a playlist to keep the music going.</p>
              <% end %>
              <ol id="playlist-tracks" phx-update="stream" class="queue-list">
                <li :for={{dom_id, track} <- @streams.playlist_items} id={dom_id} class="queue-item">
                  <img src={"https://img.youtube.com/vi/#{track.youtube_id}/mqdefault.jpg"} alt="" />
                  <div class="queue-copy"><strong title={track.title}>{track.title}</strong></div>
                </li>
              </ol>
            </section>
            <section id="room-people" class="room-people" aria-labelledby="room-people-title">
              <div class="room-people-heading">
                <h2 id="room-people-title">People in this room</h2>
                <span id="participant-count" class="participant-count" role="status">
                  {@participant_count} connected
                </span>
              </div>
              <ul id="participants" class="participant-list" phx-update="stream">
                <li :for={{dom_id, person} <- @streams.participants} id={dom_id} class="participant">
                  <span class="participant-dot" aria-hidden="true"></span>
                  <span class="participant-display-name">{person.name}</span>
                  <span :if={person.self?} class="participant-you">You</span>
                  <span :if={person.host?} class="participant-host">Host</span>
                </li>
              </ul>
              <p :if={@participant_count == 0} id="participants-empty" class="participants-empty">
                Connecting to the room…
              </p>
            </section>
          </aside>
        </main>

        <section class="add-section">
          <div class="add-copy">
            <div class="eyebrow">ADD TO THE PARTY</div><h2>What should we play next?</h2>
          </div>
          <.form
            for={@video_form}
            id="add-video"
            phx-hook="VideoForm"
            phx-submit="submit_video"
            class="add-form"
          >
            <.input
              field={@video_form[:url]}
              class="video-url-input"
              placeholder="Paste a YouTube link..."
              required
              autocomplete="off"
              aria-label="YouTube video link"
            />
            <button type="submit" phx-disable-with="Adding…">Add video
            <span aria-hidden="true">↗</span></button>
          </.form>
          <.form
            for={@name_form}
            id="participant-name"
            phx-change="set_name"
            phx-submit="set_name"
            class="identity-row"
          >
            <label for="name">Your name</label>
            <.input
              field={@name_form[:name]}
              class="participant-input"
              maxlength="24"
              phx-debounce="300"
            />
          </.form>
          <p :if={@error} id="room-error" class="error-message" role="alert">{@error}</p>
        </section>

        <footer><span>QueueParty</span><span>Everyone’s a DJ.</span></footer>
      </div>
    </Layouts.app>
    """
  end
end
