defmodule QueuePartyWeb.HomeLive do
  use QueuePartyWeb, :live_view

  alias QueueParty.Rooms

  def mount(_params, _session, socket), do: {:ok, assign(socket, code: "", error: nil)}

  def handle_event("create", _params, socket) do
    {:ok, room} = Rooms.create_room()
    {:noreply, push_navigate(socket, to: "/room/#{room.code}?host=#{room.host_token}")}
  end

  def handle_event("join", %{"code" => code}, socket) do
    code = String.upcase(String.trim(code))
    if Rooms.get_room(code), do: {:noreply, push_navigate(socket, to: "/room/#{code}")}, else: {:noreply, assign(socket, error: "We couldn’t find that room.")}
  end

  def render(assigns) do
    ~H"""
    <div class="landing">
      <nav><a class="brand" href={~p"/">Queue<span>Party</span></a><span class="nav-note">A shared listening room for the internet</span></nav>
      <main class="hero">
        <div class="hero-copy"><div class="eyebrow">YOUTUBE · TOGETHER</div><h1>Everyone’s a DJ.<br /><em>Play something.</em></h1><p>Start a room, share the code, and let the whole group build the queue from their phones.</p><div class="hero-actions"><button phx-click="create" class="primary-button">Start a room <span>↗</span></button><form phx-submit="join" class="join-form"><input name="code" placeholder="ROOM CODE" value={@code} maxlength="6" /><button>Join</button></form></div><p :if={@error} class="error-message"><%= @error %></p></div>
        <div class="hero-art"><div class="sun"></div><div class="vinyl"><div class="vinyl-label">QP</div></div><div class="sticker">SCAN<br /><strong>SHARE<br />PLAY</strong></div></div>
      </main>
      <div class="feature-strip"><span><b>01</b> Create a room</span><span><b>02</b> Share the code</span><span><b>03</b> Build the vibe</span></div>
    </div>
    """
  end
end
