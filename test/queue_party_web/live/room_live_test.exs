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

    assert has_element?(
             host,
             "#youtube-player[data-video-id='dQw4w9WgXcQ'][data-playback-status='playing']"
           )

    assert has_element?(guest, "#now-playing", "Morgan")
    refute has_element?(host, "#play-first")
    guest |> form("#add-video", url: "https://youtu.be/M7lc1UVf-VE") |> render_submit()
    assert has_element?(host, "#queue li .queue-copy small", "Morgan")
    assert has_element?(guest, "#queue li")
    refute has_element?(guest, "#play-first")
  end

  test "host playback advances once per queue item and clears after the final video", %{
    conn: conn
  } do
    {:ok, room} = Rooms.create_room()
    {:ok, first} = Rooms.add_item(room.code, "dQw4w9WgXcQ", "A")
    {:ok, second} = Rooms.add_item(room.code, "M7lc1UVf-VE", "B")
    {:ok, host, _} = live(conn, ~p"/room/#{room.code}?host=#{room.host_token}")
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

  test "guest submissions autostart everyone mode, including after the queue ends", %{conn: conn} do
    {:ok, room} = Rooms.create_room()
    Rooms.set_playback_mode(room.code, room.host_token, "everyone")
    {:ok, host, _} = live(conn, ~p"/room/#{room.code}?host=#{room.host_token}")
    {:ok, guest, _} = live(build_conn(), ~p"/room/#{room.code}")
    guest |> form("#add-video", url: "https://youtu.be/dQw4w9WgXcQ") |> render_submit()
    first = Rooms.get_room(room.code).now_playing
    assert has_element?(host, "#youtube-player[data-playback-status='playing']")
    assert has_element?(guest, "#youtube-player[data-playback-status='playing']")
    refute has_element?(host, "#play-first")
    render_hook(host, "video_ended", %{"item_id" => first.id})
    refute has_element?(host, "#youtube-player")
    guest |> form("#add-video", url: "https://youtu.be/M7lc1UVf-VE") |> render_submit()

    assert has_element?(
             host,
             "#youtube-player[data-video-id='M7lc1UVf-VE'][data-playback-status='playing']"
           )

    assert has_element?(
             guest,
             "#youtube-player[data-video-id='M7lc1UVf-VE'][data-playback-status='playing']"
           )
  end

  test "guests cannot remove, directly skip, or finish videos", %{conn: conn} do
    {:ok, room} = Rooms.create_room()
    {:ok, first} = Rooms.add_item(room.code, "dQw4w9WgXcQ", "A")
    {:ok, second} = Rooms.add_item(room.code, "M7lc1UVf-VE", "B")
    {:ok, guest, _} = live(conn, ~p"/room/#{room.code}")
    render_hook(guest, "remove", %{"id" => second.id})
    render_hook(guest, "skip", %{})
    assert Rooms.get_room(room.code).now_playing.id == first.id
    assert length(Rooms.get_room(room.code).items) == 1
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

  test "expired room invites redirect home and the join form rejects their code", %{conn: conn} do
    {:ok, room} = Rooms.create_room()
    {_, marker} = room.empty_timer
    send(Process.whereis(Rooms), {:empty_room_expired, room.code, marker})
    assert Rooms.get_room(room.code) == nil
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/room/#{room.code}")
    {:ok, home, _} = live(build_conn(), ~p"/")
    home |> form("#join-room", code: room.code) |> render_submit()
    assert has_element?(home, "#join-error")
  end

  test "only the host can change listening mode, including during playback", %{conn: conn} do
    {:ok, room} = Rooms.create_room()
    {:ok, item} = Rooms.add_item(room.code, "dQw4w9WgXcQ", "A")
    {:ok, host, _} = live(conn, ~p"/room/#{room.code}?host=#{room.host_token}")
    {:ok, guest, _} = live(build_conn(), ~p"/room/#{room.code}")

    assert has_element?(host, "#playback-settings")
    refute has_element?(guest, "#playback-settings")
    refute has_element?(guest, "#youtube-player")
    render_hook(guest, "set_playback_mode", %{"playback_mode" => "everyone"})
    assert Rooms.get_room(room.code).playback_mode == "host_only"

    host |> form("#playback-settings", playback_mode: "everyone") |> render_change()
    assert has_element?(guest, "#youtube-player[data-host='false']")
    assert has_element?(guest, "#enable-device-audio")
    assert has_element?(guest, "#playback-mode-label", "every device")
    assert Rooms.get_room(room.code).now_playing.id == item.id

    host |> form("#playback-settings", playback_mode: "host_only") |> render_change()
    refute has_element?(guest, "#youtube-player")
    refute has_element?(guest, "#enable-device-audio")
    assert has_element?(host, "#youtube-player")
    assert Rooms.get_room(room.code).now_playing.id == item.id
  end

  test "everyone mode follows host playhead and ignores guest playback reports", %{conn: conn} do
    {:ok, room} = Rooms.create_room()
    {:ok, item} = Rooms.add_item(room.code, "dQw4w9WgXcQ", "A")
    item_id = item.id
    Rooms.set_playback_mode(room.code, room.host_token, "everyone")
    {:ok, host, _} = live(conn, ~p"/room/#{room.code}?host=#{room.host_token}")
    {:ok, guest, _} = live(build_conn(), ~p"/room/#{room.code}")

    render_hook(host, "playback_update", %{item_id: item.id, status: "paused", position: 42.5})
    render(guest)

    assert_push_event(guest, "room_playback", %{
      item_id: ^item_id,
      status: "paused",
      position: 42.5,
      revision: 2
    })

    render_hook(guest, "playback_update", %{item_id: item.id, status: "playing", position: 0})
    render_hook(guest, "video_ended", %{item_id: item.id})
    assert %{status: "paused", position: 42.5} = Rooms.get_room(room.code).playback
    assert Rooms.get_room(room.code).now_playing.id == item.id

    {:ok, late_guest, _} = live(build_conn(), ~p"/room/#{room.code}")

    assert has_element?(
             late_guest,
             "#youtube-player[data-playback-status='paused'][data-playback-position='42.5']"
           )

    render_hook(host, "playback_update", %{item_id: item.id, status: "playing", position: 44})
    render(guest)

    assert_push_event(guest, "room_playback", %{item_id: ^item_id, status: "playing", revision: 3})
  end

  test "everyone mode keeps next-track advancement under host control", %{conn: conn} do
    {:ok, room} = Rooms.create_room()
    {:ok, first} = Rooms.add_item(room.code, "dQw4w9WgXcQ", "A")
    {:ok, second} = Rooms.add_item(room.code, "M7lc1UVf-VE", "B")
    Rooms.set_playback_mode(room.code, room.host_token, "everyone")
    {:ok, host, _} = live(conn, ~p"/room/#{room.code}?host=#{room.host_token}")
    {:ok, guest, _} = live(build_conn(), ~p"/room/#{room.code}")

    render_hook(guest, "video_ended", %{item_id: first.id})
    assert Rooms.get_room(room.code).now_playing.id == first.id
    render_hook(host, "video_ended", %{item_id: first.id})
    assert has_element?(guest, "#youtube-player[data-item-id='#{second.id}']")
    assert Rooms.get_room(room.code).playback.position == 0.0

    render_hook(host, "playback_update", %{item_id: first.id, status: "playing", position: 300})
    assert Rooms.get_room(room.code).playback.item_id == second.id
    assert Rooms.get_room(room.code).playback.position == 0.0
  end
end
