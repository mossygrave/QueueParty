defmodule QueueParty.YouTubePlaylistStub do
  @moduledoc false
  import Plug.Conn
  def init(options), do: options

  def call(conn, _options) do
    conn = fetch_query_params(conn)

    case conn.request_path do
      "/youtube/v3/playlists" ->
        Req.Test.json(conn, %{
          "items" => [
            %{
              "snippet" => %{"title" => "Party playlist"},
              "status" => %{"privacyStatus" => "public"}
            }
          ]
        })

      "/youtube/v3/playlistItems" ->
        Req.Test.json(conn, %{
          "items" => [
            %{
              "snippet" => %{
                "title" => "Playlist A",
                "resourceId" => %{"videoId" => "M7lc1UVf-VE"}
              }
            },
            %{
              "snippet" => %{
                "title" => "Playlist B",
                "resourceId" => %{"videoId" => "dQw4w9WgXcQ"}
              }
            }
          ]
        })
    end
  end
end
