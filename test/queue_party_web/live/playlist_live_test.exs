defmodule QueuePartyWeb.PlaylistLiveTest do
  use QueuePartyWeb.ConnCase
  import Phoenix.LiveViewTest
  alias QueueParty.Rooms
  @url "https://www.youtube.com/playlist?list=PLQueuePartyDemo"

  setup %{conn: conn} do
    {:ok, room} = Rooms.create_room()
    {:ok, host, _} = live(conn, ~p"/room/#{room.code}?host=#{room.host_token}")

    {:ok, guest, _} =
      live(init_test_session(build_conn(), %{guest_id: "playlist-guest"}), ~p"/room/#{room.code}")

    %{room: room, host: host, guest: guest}
  end

  defp load(host) do
    host |> form("#playlist-form", url: @url) |> render_submit()
    render_async(host)
  end

  test "host import starts automatically and everyone sees separate queues", %{
    room: room,
    host: host,
    guest: guest
  } do
    refute has_element?(guest, "#playlist-settings")
    load(host)
    refute has_element?(host, "#playlist-error")
    assert has_element?(host, "#playlist-title", "Party playlist")
    assert has_element?(guest, "#playlist-title", "Party playlist")
    assert has_element?(host, "#now-playing-title", "Playlist A")
    assert has_element?(guest, "#playlist-tracks li", "Playlist B")
    assert has_element?(guest, "#queue-empty")
    first = Rooms.get_room(room.code).now_playing
    guest |> form("#add-video", url: "https://youtu.be/title000003") |> render_submit()
    assert has_element?(host, "#queue li")
    assert Rooms.get_room(room.code).now_playing.id == first.id
    host |> form("#playback-settings", playback_mode: "everyone") |> render_change()
    render_hook(host, "video_ended", %{"item_id" => first.id})
    assert has_element?(guest, "#youtube-player[data-video-id='title000003']")
    host |> element("#skip-video") |> render_click()
    assert has_element?(host, "#now-playing-title", "Playlist B")
    assert has_element?(guest, "#youtube-player[data-video-id='dQw4w9WgXcQ']")
  end

  test "repeat, removal, invalid URLs and guest attempts preserve host control", %{
    room: room,
    host: host,
    guest: guest
  } do
    load(host)
    host |> form("#playlist-repeat-form", repeat: true) |> render_change()
    assert Rooms.get_room(room.code).playlist.repeat?
    render_hook(guest, "remove_playlist", %{})
    render_hook(guest, "playlist_repeat", %{"repeat" => "false"})
    render_hook(guest, "load_playlist", %{"url" => @url})
    assert Rooms.get_room(room.code).playlist.repeat?
    current = Rooms.get_room(room.code).now_playing

    host
    |> form("#playlist-form", url: "https://example.com/playlist?list=PLQueuePartyDemo")
    |> render_submit()

    assert has_element?(host, "#playlist-error")
    assert Rooms.get_room(room.code).playlist.title == "Party playlist"
    host |> element("#remove-playlist") |> render_click()
    assert has_element?(guest, "#no-playlist")
    assert Rooms.get_room(room.code).now_playing.id == current.id
    host |> element("#skip-video") |> render_click()
    refute has_element?(host, "#youtube-player")
  end

  test "only the host can retire unavailable playlist entries, with stale errors ignored", %{
    room: room,
    host: host,
    guest: guest
  } do
    load(host)
    current = Rooms.get_room(room.code).now_playing
    render_hook(guest, "player_error", %{"item_id" => current.id, "code" => 150})
    assert Rooms.get_room(room.code).now_playing.id == current.id
    render_hook(host, "player_error", %{"item_id" => current.id, "code" => 150})
    assert has_element?(host, "#now-playing-title", "Playlist B")
    next = Rooms.get_room(room.code).now_playing
    render_hook(host, "player_error", %{"item_id" => current.id, "code" => 150})
    assert Rooms.get_room(room.code).now_playing.id == next.id
  end

  test "missing server key is explained and individual requests still work", %{room: room} do
    previous = Application.get_env(:queue_party, :youtube_api_key)
    Application.delete_env(:queue_party, :youtube_api_key)
    on_exit(fn -> Application.put_env(:queue_party, :youtube_api_key, previous) end)

    {:ok, host, _} =
      live(
        init_test_session(build_conn(), %{guest_id: Rooms.get_room(room.code).host_guest_id}),
        ~p"/room/#{room.code}"
      )

    assert has_element?(host, "#playlist-api-warning")
    load(host)
    assert has_element?(host, "#playlist-error", "YOUTUBE_API_KEY")
    host |> form("#add-video", url: "https://youtu.be/title000003") |> render_submit()
    assert has_element?(host, "#youtube-player[data-video-id='title000003']")
  end
end
