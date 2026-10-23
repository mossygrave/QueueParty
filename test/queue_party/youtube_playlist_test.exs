defmodule QueueParty.YouTubePlaylistTest do
  use ExUnit.Case, async: true
  alias QueueParty.YouTubePlaylist
  import Plug.Conn
  @url "https://www.youtube.com/playlist?list=PLQueuePartyDemo"

  defp fetch(options \\ []),
    do:
      YouTubePlaylist.fetch(
        @url,
        Keyword.merge([api_key: "test-key", plug: {Req.Test, __MODULE__}], options)
      )

  defp item(id, title),
    do: %{"snippet" => %{"title" => title, "resourceId" => %{"videoId" => id}}}

  defp public(conn),
    do:
      Req.Test.json(conn, %{
        "items" => [
          %{"snippet" => %{"title" => "Party"}, "status" => %{"privacyStatus" => "public"}}
        ]
      })

  test "validates playlist links without accepting other domains, schemes, or dynamic mixes" do
    for url <- [
          @url,
          "youtube.com/watch?v=M7lc1UVf-VE&list=PLQueuePartyDemo",
          "https://youtu.be/M7lc1UVf-VE?list=PLQueuePartyDemo"
        ] do
      assert {:ok, "PLQueuePartyDemo"} = YouTubePlaylist.playlist_id(url)
    end

    for url <- [
          nil,
          "",
          "https://evil.example/?list=PLQueuePartyDemo",
          "ftp://youtube.com/?list=PLQueuePartyDemo",
          "https://youtube.com/playlist?list=RDQueuePartyMix",
          "https://youtube.com/playlist?list=short"
        ] do
      assert {:error, :invalid_url} = YouTubePlaylist.playlist_id(url)
    end
  end

  test "imports metadata and all pages in order, filtering unavailable entries" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert get_req_header(conn, "x-goog-api-key") == ["test-key"]
      conn = fetch_query_params(conn)

      case {conn.request_path, conn.query_params["pageToken"]} do
        {"/youtube/v3/playlists", nil} ->
          public(conn)

        {"/youtube/v3/playlistItems", nil} ->
          assert conn.query_params["maxResults"] == "50"

          Req.Test.json(conn, %{
            "items" => [item("M7lc1UVf-VE", "A"), item("dQw4w9WgXcQ", "Private video")],
            "nextPageToken" => "page2"
          })

        {"/youtube/v3/playlistItems", "page2"} ->
          Req.Test.json(conn, %{"items" => [item("dQw4w9WgXcQ", "B")]})
      end
    end)

    assert {:ok, playlist} = fetch()
    assert playlist.title == "Party"
    assert playlist.id == "PLQueuePartyDemo"
    assert Enum.map(playlist.tracks, & &1.title) == ["A", "B"]
  end

  test "missing key and nonpublic playlists are rejected" do
    assert {:error, :missing_api_key} = fetch(api_key: nil)

    for privacy <- ["private", "unlisted"] do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{
          "items" => [
            %{"snippet" => %{"title" => "Private"}, "status" => %{"privacyStatus" => privacy}}
          ]
        })
      end)

      assert {:error, :not_public} = fetch()
    end
  end

  test "API denial, rate limits, and timeouts are actionable errors" do
    for status <- [403, 429] do
      Req.Test.stub(__MODULE__, fn conn -> send_resp(conn, status, "denied") end)
      assert {:error, :api_access} = fetch()
    end

    Req.Test.stub(__MODULE__, fn conn -> Req.Test.transport_error(conn, :timeout) end)
    assert {:error, :unavailable} = fetch()
  end

  test "imports are all-or-nothing with a 200-entry limit" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn = fetch_query_params(conn)

      if conn.request_path == "/youtube/v3/playlists" do
        public(conn)
      else
        page = String.to_integer(conn.query_params["pageToken"] || "1")

        Req.Test.json(conn, %{
          "items" => List.duplicate(item("M7lc1UVf-VE", "A"), 50),
          "nextPageToken" => to_string(page + 1)
        })
      end
    end)

    assert {:error, :too_large} = fetch()
  end

  test "empty playlists and repeated pagination tokens do not hang" do
    Req.Test.stub(__MODULE__, fn conn ->
      if conn.request_path == "/youtube/v3/playlists",
        do: public(conn),
        else: Req.Test.json(conn, %{"items" => []})
    end)

    assert {:error, :empty} = fetch()

    Req.Test.stub(__MODULE__, fn conn ->
      if conn.request_path == "/youtube/v3/playlists",
        do: public(conn),
        else:
          Req.Test.json(conn, %{"items" => [item("M7lc1UVf-VE", "A")], "nextPageToken" => "same"})
    end)

    assert {:error, :invalid_response} = fetch()
  end

  test "exactly 200 entries are accepted, and later-page failures do not return partial imports" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn = fetch_query_params(conn)

      if conn.request_path == "/youtube/v3/playlists" do
        public(conn)
      else
        page = String.to_integer(conn.query_params["pageToken"] || "1")
        body = %{"items" => List.duplicate(item("M7lc1UVf-VE", "Page #{page}"), 50)}
        body = if page < 4, do: Map.put(body, "nextPageToken", to_string(page + 1)), else: body
        Req.Test.json(conn, body)
      end
    end)

    assert {:ok, playlist} = fetch()
    assert length(playlist.tracks) == 200

    Req.Test.stub(__MODULE__, fn conn ->
      conn = fetch_query_params(conn)

      cond do
        conn.request_path == "/youtube/v3/playlists" ->
          public(conn)

        conn.query_params["pageToken"] ->
          send_resp(conn, 503, "Unavailable")

        true ->
          Req.Test.json(conn, %{"items" => [item("M7lc1UVf-VE", "A")], "nextPageToken" => "page2"})
      end
    end)

    assert {:error, :unavailable} = fetch()
  end
end
