defmodule QueueParty.YouTubeStub do
  @moduledoc false
  import Plug.Conn

  def init(options), do: options

  def call(conn, _options) do
    conn = fetch_query_params(conn)

    case conn.query_params["url"] do
      "https://www.youtube.com/watch?v=title000001" ->
        Req.Test.json(conn, %{"title" => "First song & live performance 🎵"})

      "https://www.youtube.com/watch?v=title000002" ->
        Req.Test.json(conn, %{"title" => "Second song <not HTML>"})

      _ ->
        send_resp(conn, 404, "Not found")
    end
  end
end
