defmodule QueuePartyWeb.ParticipantsLiveTest do
  use QueuePartyWeb.ConnCase
  import Phoenix.LiveViewTest
  alias QueueParty.Rooms

  setup do
    {:ok, room} = Rooms.create_room()
    host_conn = init_test_session(build_conn(), %{guest_id: "people-host"})
    guest_conn = init_test_session(build_conn(), %{guest_id: "people-guest"})
    {:ok, host, _} = live(host_conn, ~p"/room/#{room.code}?host=#{room.host_token}")
    {:ok, guest, _} = live(guest_conn, ~p"/room/#{room.code}")
    %{room: room, host: host, guest: guest, guest_conn: guest_conn}
  end

  test "everyone sees connected names, count, and viewer-specific host and you badges", %{
    host: host,
    guest: guest
  } do
    host |> form("#participant-name", name: "Morgan") |> render_change()
    guest |> form("#participant-name", name: "Ada") |> render_change()

    for view <- [host, guest] do
      assert has_element?(view, "#room-people #participant-count", "2 connected")

      assert has_element?(
               view,
               "#participants-people-host:first-child .participant-display-name",
               "Morgan"
             )

      assert has_element?(view, "#participants-people-host .participant-host", "Host")
      assert has_element?(view, "#participants-people-guest .participant-display-name", "Ada")
      refute has_element?(view, "#participants-people-guest .participant-host")
    end

    assert has_element?(host, "#participants-people-host .participant-you", "You")
    refute has_element?(guest, "#participants-people-host .participant-you")
    assert has_element?(guest, "#participants-people-guest .participant-you", "You")
    guest |> form("#participant-name", name: "<b>Ada</b>") |> render_change()

    assert has_element?(
             host,
             "#participants-people-guest .participant-display-name",
             "<b>Ada</b>"
           )

    refute has_element?(host, "#participants-people-guest b")
  end

  test "multiple tabs count once and the person leaves only after their last tab disconnects", %{
    room: room,
    host: host,
    guest: guest,
    guest_conn: guest_conn
  } do
    {:ok, second_tab, _} = live(guest_conn, ~p"/room/#{room.code}")
    assert has_element?(host, "#participant-count", "2 connected")
    Rooms.subscribe(room.code)
    stop_view(guest)
    assert_receive {:room_updated, _}
    assert has_element?(host, "#participants-people-guest")
    assert has_element?(host, "#participant-count", "2 connected")
    stop_view(second_tab)
    assert_receive {:room_updated, _}
    refute has_element?(host, "#participants-people-guest")
    assert has_element?(host, "#participant-count", "1 connected")
    {:ok, returned, _} = live(guest_conn, ~p"/room/#{room.code}")
    assert has_element?(host, "#participants-people-guest")
    assert has_element?(returned, "#participant-count", "2 connected")
  end

  test "host badges follow manual transfer for every viewer", %{
    room: room,
    host: host,
    guest: guest
  } do
    Rooms.transfer_host(room.code, room.host_token, "people-guest")

    for view <- [host, guest] do
      assert has_element?(view, "#participants-people-guest:first-child .participant-host")
      refute has_element?(view, "#participants-people-host .participant-host")
      assert has_element?(view, "#participant-count", "2 connected")
    end
  end

  test "disconnected hosts disappear and the automatic successor receives the badge", %{
    room: room,
    host: host,
    guest: guest
  } do
    Rooms.subscribe(room.code)
    stop_view(host)
    assert_receive {:room_updated, %{host_status: "reconnecting", host_timer: {_, marker}}}
    refute has_element?(guest, "#participants-people-host")
    assert has_element?(guest, "#participant-count", "1 connected")
    refute has_element?(guest, "#participants .participant-host")
    send(Process.whereis(Rooms), {:host_grace_expired, room.code, marker})
    assert_receive {:room_updated, %{host_guest_id: "people-guest", host_status: "online"}}
    assert has_element?(guest, "#participants-people-guest .participant-host")
  end

  defp stop_view(view) do
    ref = Process.monitor(view.pid)
    GenServer.stop(view.pid, :normal)
    assert_receive {:DOWN, ^ref, :process, _, :normal}
  end
end
