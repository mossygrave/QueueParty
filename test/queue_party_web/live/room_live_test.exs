defmodule QueuePartyWeb.RoomLiveTest do
  use QueuePartyWeb.ConnCase
  import Phoenix.LiveViewTest
  alias QueueParty.Rooms

  test "create and join routes work", %{conn: conn} do
    {:ok, home, _} = live(conn, ~p"/")
    home |> element("#create-room") |> render_click()
    {path, _flash} = assert_redirect(home)
    assert path =~ "/room/"
    assert path =~ "host="
    {:ok, host, _} = live(conn, path)
    assert has_element?(host, "#add-video")
  end

  test "guest submissions update the host queue and display name", %{conn: conn} do
    {:ok, room} = Rooms.create_room()
    {:ok, host, _} = live(conn, ~p"/room/#{room.code}?host=#{room.host_token}")
    {:ok, guest, _} = live(build_conn(), ~p"/room/#{room.code}")
    guest |> form("#participant-name", name: "Morgan") |> render_change()
    guest |> form("#add-video", url: "https://youtu.be/dQw4w9WgXcQ") |> render_submit()
    assert has_element?(host, "#queue li .queue-copy small", "Morgan")
    assert has_element?(guest, "#queue li")
    assert has_element?(host, "#play-first")
    refute has_element?(guest, "#play-first")
  end

  test "host playback advances once per queue item and clears after the final video", %{
    conn: conn
  } do
    {:ok, room} = Rooms.create_room()
    {:ok, first} = Rooms.add_item(room.code, "dQw4w9WgXcQ", "A")
    {:ok, second} = Rooms.add_item(room.code, "M7lc1UVf-VE", "B")
    {:ok, host, _} = live(conn, ~p"/room/#{room.code}?host=#{room.host_token}")
    host |> element("#play-first") |> render_click()
    assert has_element?(host, "#youtube-player[data-video-id='dQw4w9WgXcQ']")
    render_hook(host, "video_ended", %{"item_id" => first.id})
    assert has_element?(host, "#youtube-player[data-video-id='M7lc1UVf-VE']")
    render_hook(host, "video_ended", %{"item_id" => first.id})
    assert Rooms.get_room(room.code).now_playing.id == second.id
    render_hook(host, "video_ended", %{"item_id" => second.id})
    assert has_element?(host, "#queue-empty")
    refute has_element?(host, "#youtube-player")
    assert Rooms.get_room(room.code).now_playing == nil
  end

  test "guests cannot remove, start, or finish videos", %{conn: conn} do
    {:ok, room} = Rooms.create_room()
    {:ok, first} = Rooms.add_item(room.code, "dQw4w9WgXcQ", "A")
    {:ok, guest, _} = live(conn, ~p"/room/#{room.code}")
    render_hook(guest, "remove", %{"id" => first.id})
    render_hook(guest, "skip", %{})
    assert Rooms.get_room(room.code).now_playing == nil
    assert length(Rooms.get_room(room.code).items) == 1
    Rooms.skip(room.code)
    render_hook(guest, "video_ended", %{"item_id" => first.id})
    assert Rooms.get_room(room.code).now_playing.id == first.id
    refute has_element?(guest, "#youtube-player")
    refute has_element?(guest, "#skip-video")
  end

  test "missing room redirects and invalid link preserves input", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/room/MISSING")
    {:ok, room} = Rooms.create_room()
    {:ok, guest, _} = live(build_conn(), ~p"/room/#{room.code}")
    guest |> form("#add-video", url: "https://example.com/no-video") |> render_submit()
    assert has_element?(guest, "#room-error")
    assert has_element?(guest, "#queue-empty")
  end
end
