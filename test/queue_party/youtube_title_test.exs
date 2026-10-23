defmodule QueueParty.YouTubeTitleTest do
  use ExUnit.Case, async: true
  alias QueueParty.YouTube
  import Plug.Conn

  defp fetch(id \\ "M7lc1UVf-VE"),
    do: YouTube.fetch_title(id, plug: {Req.Test, __MODULE__})

  test "fetches the title from the fixed YouTube endpoint using a canonical video URL" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.host == "www.youtube.com"
      assert conn.request_path == "/oembed"
      conn = fetch_query_params(conn)

      assert conn.query_params == %{
               "format" => "json",
               "url" => "https://www.youtube.com/watch?v=M7lc1UVf-VE"
             }

      Req.Test.json(conn, %{"title" => "  Song & artist — live 🎵  "})
    end)

    assert fetch() == {:ok, "Song & artist — live 🎵"}
  end

  test "private, missing, rate-limited, and failed responses return a safe fallback result" do
    for status <- [401, 403, 404, 429, 500] do
      Req.Test.stub(__MODULE__, fn conn -> send_resp(conn, status, "Unavailable") end)
      assert fetch() == :error
    end
  end

  test "empty or invalid metadata does not become a video title" do
    for body <- [
          %{},
          %{"title" => nil},
          %{"title" => 123},
          %{"title" => ""},
          %{"title" => " \n "},
          []
        ] do
      Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, body) end)
      assert fetch() == :error
    end

    Req.Test.stub(__MODULE__, fn conn ->
      conn |> put_resp_content_type("application/json") |> send_resp(200, "{bad json")
    end)

    assert fetch() == :error
  end

  test "timeouts and connection failures do not raise" do
    for reason <- [:timeout, :econnrefused] do
      Req.Test.stub(__MODULE__, fn conn -> Req.Test.transport_error(conn, reason) end)
      assert fetch() == :error
    end
  end

  test "invalid IDs never trigger HTTP requests" do
    Req.Test.stub(__MODULE__, fn _ -> flunk("Invalid video ID triggered a request") end)

    for id <- [nil, "", "short", "https://example.com", "M7lc1UVf-VE&other=value"] do
      assert fetch(id) == :error
    end
  end

  test "titles are length-limited and returned as plain text" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"title" => String.duplicate("🎵", 600)})
    end)

    assert {:ok, title} = fetch()
    assert String.length(title) == 500

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"title" => "<script>alert('x')</script>"})
    end)

    assert fetch() == {:ok, "<script>alert('x')</script>"}
  end

  test "the production HTTP adapter works with the configured timeout options" do
    server =
      start_supervised!(
        {Bandit,
         plug: fn conn, _opts -> Req.Test.json(conn, %{"title" => "Over HTTP"}) end,
         ip: {127, 0, 0, 1},
         port: 0}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    assert YouTube.fetch_title("M7lc1UVf-VE", url: "http://127.0.0.1:#{port}/oembed", plug: nil) ==
             {:ok, "Over HTTP"}
  end
end
