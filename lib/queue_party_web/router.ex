defmodule QueuePartyWeb.Router do
  use QueuePartyWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :ensure_guest_id
    plug :fetch_live_flash
    plug :put_root_layout, html: {QueuePartyWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  defp ensure_guest_id(conn, _opts) do
    if get_session(conn, :guest_id) do
      conn
    else
      put_session(
        conn,
        :guest_id,
        Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      )
    end
  end

  scope "/", QueuePartyWeb do
    pipe_through :browser

    live "/", HomeLive
    live "/room/:code", RoomLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", QueuePartyWeb do
  #   pipe_through :api
  # end
end
