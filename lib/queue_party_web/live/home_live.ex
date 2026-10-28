defmodule QueuePartyWeb.HomeLive do
  use QueuePartyWeb, :live_view

  alias QueueParty.Rooms

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, join_form: to_form(%{"code" => ""}), error: nil)}
  end

  @impl true
  def handle_event("create", _params, socket) do
    {:ok, room} = Rooms.create_room()
    {:noreply, push_navigate(socket, to: ~p"/room/#{room.code}?host=#{room.host_token}")}
  end

  def handle_event("join", %{"code" => code}, socket) do
    code = String.upcase(String.trim(code))

    if Rooms.get_room(code) do
      {:noreply, push_navigate(socket, to: ~p"/room/#{code}")}
    else
      {:noreply,
       assign(socket, join_form: to_form(%{"code" => code}), error: "We couldn’t find that room.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="landing">
        <nav>
          <.link navigate={~p"/"} class="brand">Queue<span>Party</span></.link>
          <span class="nav-note">Shared listening and watching</span>
        </nav>
        <main class="hero">
          <div class="hero-copy">
            <div class="eyebrow"></div>
            <h1 id="home-title">Watch<br /><em>together</em></h1>
            <p id="home-description">Add YouTube links to a shared queue</p>
            <div class="hero-actions">
              <button id="create-room" phx-click="create" class="primary-button">
                Start a room <span aria-hidden="true">↗</span>
              </button>
              <.form for={@join_form} id="join-room" phx-submit="join" class="join-form">
                <.input
                  field={@join_form[:code]}
                  class="room-code-input"
                  placeholder="ROOM CODE"
                  maxlength="5"
                  required
                  aria-label="Room code"
                />
                <button type="submit">Join</button>
              </.form>
            </div>
            <p :if={@error} id="join-error" class="error-message" role="alert">{@error}</p>
          </div>
          <div class="hero-art" aria-hidden="true">
            <div class="sun"></div>
            <div class="vinyl">
              <div class="vinyl-label">QP</div>
            </div>
            <div class="sticker">SHARE<br /><strong>QUEUE<br />PLAY</strong></div>
          </div>
        </main>
      </div>
    </Layouts.app>
    """
  end
end
