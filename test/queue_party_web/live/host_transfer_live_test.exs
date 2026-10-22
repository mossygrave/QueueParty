defmodule QueuePartyWeb.HostTransferLiveTest do
  use QueuePartyWeb.ConnCase
  import Phoenix.LiveViewTest
  alias QueueParty.Rooms

  setup do
    {:ok, room} = Rooms.create_room()
    host_conn = init_test_session(build_conn(), %{guest_id: "host"})
    guest_conn = init_test_session(build_conn(), %{guest_id: "guest"})
    {:ok, host, _} = live(host_conn, ~p"/room/#{room.code}?host=#{room.host_token}")
    {:ok, guest, _} = live(guest_conn, ~p"/room/#{room.code}")
    %{room: room, host: host, guest: guest, guest_conn: guest_conn}
  end

  test "host transfers to a connected guest and old URL no longer controls the room", %{
    room: room,
    host: host,
    guest: guest,
    guest_conn: guest_conn
  } do
    guest |> form("#participant-name", name: "Morgan") |> render_change()
    assert has_element?(host, "#transfer-host-guest option[value='guest']", "Morgan")
    refute has_element?(guest, "#transfer-host-form")
    {:ok, item} = Rooms.add_item(room.code, "dQw4w9WgXcQ", "A")
    assert has_element?(host, "#youtube-player[data-host='true']")
    host |> form("#transfer-host-form", guest_id: "guest") |> render_submit()
    refute has_element?(host, "#room-settings")
    refute has_element?(host, "#youtube-player")
    assert has_element?(guest, "#room-settings")
    assert has_element?(guest, "#youtube-player[data-host='true']")
    assert Rooms.get_room(room.code).now_playing.id == item.id
    render_hook(host, "skip", %{})
    render_hook(host, "transfer_host", %{"guest_id" => "host"})
    assert Rooms.get_room(room.code).now_playing.id == item.id
    assert Rooms.get_room(room.code).host_guest_id == "guest"

    {:ok, old_link, _} =
      live(
        init_test_session(build_conn(), %{guest_id: "other"}),
        ~p"/room/#{room.code}?host=#{room.host_token}"
      )

    refute has_element?(old_link, "#room-settings")
    {:ok, returned, _} = live(guest_conn, ~p"/room/#{room.code}")
    assert has_element?(returned, "#room-settings")
  end

  test "disconnect shows grace notice and automatic successor receives controls", %{
    room: room,
    host: host,
    guest: guest
  } do
    Rooms.subscribe(room.code)
    ref = Process.monitor(host.pid)
    GenServer.stop(host.pid, :normal)
    assert_receive {:DOWN, ^ref, :process, _, :normal}
    assert_receive {:room_updated, %{host_status: "reconnecting", host_timer: {_, marker}}}
    assert has_element?(guest, "#host-status[data-status='reconnecting']")
    send(Process.whereis(Rooms), {:host_grace_expired, room.code, marker})
    assert_receive {:room_updated, %{host_status: "online", host_guest_id: "guest"}}
    assert has_element?(guest, "#host-status[data-status='online']")
    assert has_element?(guest, "#room-settings")
  end

  test "guest cannot steal ownership by submitting the transfer event", %{
    room: room,
    guest: guest
  } do
    render_hook(guest, "transfer_host", %{"guest_id" => "guest"})
    assert Rooms.get_room(room.code).host_guest_id == "host"
    refute has_element?(guest, "#room-settings")
  end
end
