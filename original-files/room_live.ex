defmodule QueuePartyWeb.RoomLive do
  use QueuePartyWeb, :live_view

  alias QueueParty.Rooms

  @impl true
  def mount(%{"code" => code} = params, _session, socket) do
    code = String.upcase(code)
    room = Rooms.get_room(code)

    if room do
      if connected?(socket), do: Rooms.subscribe(code)

      {:ok,
       socket
       |> assign(:room, room)
       |> assign(:code, code)
       |> assign(:is_host, params["host"] == room.host_token)
       |> assign(:name, "Guest #{Enum.random(100..999)}")
       |> assign(:url, "")
       |> assign(:error, nil)}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  @impl true
  def handle_event("submit_video", %{"url" => url}, socket) do
    case youtube_id(url) do
      {:ok, id} ->
        case Rooms.add_item(socket.assigns.code, id, socket.assigns.name) do
          {:ok, _item} -> {:noreply, assign(socket, url: "", error: nil)}
          {:error, _} -> {:noreply, assign(socket, error: "This room is no longer available.")}
        end

      :error -> {:noreply, assign(socket, error: "Paste a valid YouTube link.")}
    end
  end

  def handle_event("set_name", %{"name" => name}, socket), do: {:noreply, assign(socket, :name, String.slice(name, 0, 24))}

  def handle_event("remove", %{"id" => id}, socket) do
    if socket.assigns.is_host, do: Rooms.remove_item(socket.assigns.code, id)
    {:noreply, socket}
  end

  def handle_event("skip", _params, socket) do
    if socket.assigns.is_host, do: Rooms.skip(socket.assigns.code)
    {:noreply, socket}
  end

  def handle_event("video_ended", _params, socket) do
    if socket.assigns.is_host, do: Rooms.skip(socket.assigns.code)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:room_updated, room}, socket), do: {:noreply, assign(socket, :room, room)}

  def render(assigns) do
    ~H"""
    <div class="app-shell room-shell">
      <header class="topbar">
        <a class="brand" href={~p"/"}>Queue<span>Party</span></a>
        <div class="room-badge">ROOM <strong><%= @code %></strong></div>
      </header>

      <main class="room-layout">
        <section class="player-panel">
          <div class="eyebrow">NOW PLAYING</div>
          <div :if={@room.now_playing} id="youtube-player" class="player-frame" phx-hook="YouTubePlayer" data-video-id={@room.now_playing.youtube_id}>
          </div>
          <div :if={!@room.now_playing} class="empty-player">
            <div class="play-orb">▶</div>
            <h1>Drop a song into the room</h1>
            <p>The first link submitted will be ready for the host to play.</p>
          </div>
          <div class="player-meta" :if={@room.now_playing}>
            <div><span class="live-dot"></span> Playing from the shared queue</div>
            <button :if={@is_host} phx-click="skip" class="text-button">Skip to next →</button>
          </div>
          <button :if={@is_host && !@room.now_playing && @room.items != []} phx-click="skip" class="play-first">Play first video →</button>
        </section>

        <aside class="queue-panel">
          <div class="queue-heading">
            <div><div class="eyebrow">UP NEXT</div><h2><%= length(@room.items) %> videos</h2></div>
            <span class="people-pill">● live room</span>
          </div>
          <div :if={@room.items == []} class="queue-empty">The queue is empty.<br /><span>Be the first to add something.</span></div>
          <ol class="queue-list">
            <li :for={{item, index} <- Enum.with_index(@room.items)} class="queue-item">
              <span class="queue-number"><%= index + 1 %></span>
              <img src={"https://img.youtube.com/vi/#{item.youtube_id}/mqdefault.jpg"} alt="" />
              <div class="queue-copy"><strong><%= item.title %></strong><small>added by <%= item.submitted_by %></small></div>
              <button :if={@is_host} phx-click="remove" phx-value-id={item.id} class="remove-button" aria-label="Remove video">×</button>
            </li>
          </ol>
        </aside>
      </main>

      <section class="add-section">
        <div class="add-copy"><div class="eyebrow">ADD TO THE PARTY</div><h2>What should we play next?</h2></div>
        <form phx-submit="submit_video" class="add-form">
          <input name="url" value={@url} placeholder="Paste a YouTube link..." autocomplete="off" />
          <button type="submit">Add video <span>↗</span></button>
        </form>
        <div class="identity-row"><label>Your name</label><input value={@name} phx-change="set_name" name="name" maxlength="24" /></div>
        <p :if={@error} class="error-message"><%= @error %></p>
      </section>

      <footer><span>QueueParty</span><span>Everyone’s a DJ.</span></footer>
    </div>
    """
  end

  defp youtube_id(url) do
    cond do
      match = Regex.run(~r/(?:youtu\.be\/|youtube\.com\/(?:watch\?v=|shorts\/|embed\/))([\w-]{11})/, url) -> {:ok, Enum.at(match, 1)}
      true -> :error
    end
  end
end
