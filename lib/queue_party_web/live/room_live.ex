defmodule QueuePartyWeb.RoomLive do
  use QueuePartyWeb, :live_view

  alias QueueParty.{Rooms, YouTube}

  @impl true
  def mount(%{"code" => code} = params, _session, socket) do
    code = String.upcase(code)
    if connected?(socket), do: Rooms.subscribe(code)

    case Rooms.get_room(code) do
      nil ->
        {:ok, socket |> put_flash(:error, "That room no longer exists.") |> redirect(to: ~p"/")}

      room ->
        {:ok,
         socket
         |> assign(:code, code)
         |> assign(:host?, params["host"] == room.host_token)
         |> assign(:video_form, to_form(%{"url" => ""}))
         |> assign(:name_form, to_form(%{"name" => "Guest #{Enum.random(100..999)}"}))
         |> assign(:error, nil)
         |> assign_room(room)}
    end
  end

  @impl true
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
    {:noreply, assign(socket, :name_form, to_form(%{"name" => name}))}
  end

  def handle_event("remove", %{"id" => id}, socket) do
    if socket.assigns.host?, do: Rooms.remove_item(socket.assigns.code, id)
    {:noreply, socket}
  end

  def handle_event("skip", _params, socket) do
    if socket.assigns.host?, do: Rooms.skip(socket.assigns.code)
    {:noreply, assign(socket, :error, nil)}
  end

  def handle_event("video_ended", %{"item_id" => item_id}, socket) do
    if socket.assigns.host?, do: Rooms.finish(socket.assigns.code, item_id)
    {:noreply, socket}
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

  defp assign_room(socket, room) do
    items =
      Enum.with_index(room.items, 1)
      |> Enum.map(fn {item, position} -> Map.put(item, :position, position) end)

    socket
    |> assign(:now_playing, room.now_playing)
    |> assign(:queue_count, length(items))
    |> stream(:items, items, reset: true)
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
          </div>
        </header>

        <main class="room-layout">
          <section class="player-panel">
            <div class="eyebrow">NOW PLAYING · {if @host?, do: "HOST", else: "GUEST"}</div>
            <div
              :if={@host? && @now_playing}
              id="youtube-player"
              class="player-frame"
              phx-hook="YouTubePlayer"
              phx-update="ignore"
              data-video-id={@now_playing.youtube_id}
              data-item-id={@now_playing.id}
            >
            </div>
            <div :if={!@host? && @now_playing} class="guest-playing">
              <img
                src={"https://img.youtube.com/vi/#{@now_playing.youtube_id}/hqdefault.jpg"}
                alt="Current video thumbnail"
              />
              <p>Playing on the host’s device</p>
            </div>
            <div :if={!@now_playing} class="empty-player">
              <div class="play-orb" aria-hidden="true">▶</div>
              <h1>Drop a song into the room</h1>
              <p>The host starts playback once a video is queued.</p>
            </div>
            <div :if={@now_playing} id="now-playing" class="player-meta">
              <div><span class="live-dot"></span>Added by {@now_playing.submitted_by}</div>
              <button :if={@host?} id="skip-video" phx-click="skip" class="text-button">Skip to next →</button>
            </div>
            <button
              :if={@host? && !@now_playing && @queue_count > 0}
              id="play-first"
              phx-click="skip"
              class="play-first"
            >Play first video →</button>
          </section>

          <aside class="queue-panel">
            <div class="queue-heading">
              <div>
                <div class="eyebrow">UP NEXT</div><h2>{@queue_count} videos</h2>
              </div>
              <span class="people-pill">● live room</span>
            </div>
            <div :if={@queue_count == 0} id="queue-empty" class="queue-empty">
              The queue is empty.<br /><span>Be the first to add something.</span>
            </div>
            <ol id="queue" class="queue-list" phx-update="stream">
              <li :for={{dom_id, item} <- @streams.items} id={dom_id} class="queue-item">
                <span class="queue-number">{item.position}</span>
                <img src={"https://img.youtube.com/vi/#{item.youtube_id}/mqdefault.jpg"} alt="" />
                <div class="queue-copy">
                  <strong>{item.title}</strong><small>added by {item.submitted_by}</small>
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
