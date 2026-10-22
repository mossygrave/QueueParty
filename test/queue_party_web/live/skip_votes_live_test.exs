defmodule QueuePartyWeb.SkipVotesLiveTest do
  use QueuePartyWeb.ConnCase
  import Phoenix.LiveViewTest
  alias QueueParty.Rooms

  setup do
    {:ok, room} = Rooms.create_room()
    {:ok, first} = Rooms.add_item(room.code, "dQw4w9WgXcQ", "A")
    {:ok, second} = Rooms.add_item(room.code, "M7lc1UVf-VE", "B")
    {:ok, host, _} = live(build_conn(), ~p"/room/#{room.code}?host=#{room.host_token}")
    guest_conn = init_test_session(build_conn(), %{guest_id: "guest-a"})
    {:ok, guest, _} = live(guest_conn, ~p"/room/#{room.code}")
    %{room: room, first: first, second: second, host: host, guest: guest, guest_conn: guest_conn}
  end

  test "guests request once per session across refreshes and host approves", %{
    room: room,
    first: first,
    second: second,
    host: host,
    guest: guest,
    guest_conn: guest_conn
  } do
    refute has_element?(guest, "#skip-settings")
    refute has_element?(host, "#request-skip")
    guest |> element("#request-skip") |> render_click()
    assert has_element?(guest, "#request-skip[disabled]")
    assert has_element?(host, "#skip-vote-count", "1 / 3")
    assert has_element?(host, "#approve-skip")
    {:ok, refreshed, _} = live(guest_conn, ~p"/room/#{room.code}")
    assert has_element?(refreshed, "#request-skip[disabled]")
    render_hook(refreshed, "request_skip", %{"item_id" => first.id, "guest_id" => "forged"})
    assert MapSet.size(Rooms.get_room(room.code).skip_votes) == 1
    host |> element("#approve-skip") |> render_click()
    assert Rooms.get_room(room.code).now_playing.id == second.id
    assert has_element?(guest, "#request-skip:not([disabled])")
    assert has_element?(guest, "#skip-vote-count", "0 / 3")
    refute has_element?(host, "#approve-skip")
  end

  test "host configures threshold and unique guests trigger automatic skip", %{
    room: room,
    second: second,
    host: host,
    guest: guest
  } do
    host |> form("#skip-settings", skip_threshold: "2") |> render_submit()
    assert has_element?(guest, "#skip-vote-count", "0 / 2")
    guest |> element("#request-skip") |> render_click()

    {:ok, other, _} =
      live(init_test_session(build_conn(), %{guest_id: "guest-b"}), ~p"/room/#{room.code}")

    other |> element("#request-skip") |> render_click()
    assert Rooms.get_room(room.code).now_playing.id == second.id
    assert has_element?(host, "#skip-vote-count", "0 / 2")
    assert has_element?(guest, "#request-skip:not([disabled])")
  end

  test "guest cannot configure or approve, and invalid host settings leave state unchanged", %{
    room: room,
    first: first,
    host: host,
    guest: guest
  } do
    render_hook(guest, "set_skip_threshold", %{"skip_threshold" => "1"})
    render_hook(guest, "approve_skip", %{"item_id" => first.id})
    assert Rooms.get_room(room.code).skip_threshold == 3
    assert Rooms.get_room(room.code).now_playing.id == first.id

    for invalid <- ["0", "101", "2.5", "abc"] do
      host |> form("#skip-settings", skip_threshold: invalid) |> render_submit()
      assert Rooms.get_room(room.code).skip_threshold == 3
    end
  end

  test "router assigns a stable guest identity in the signed session", %{conn: conn} do
    conn = get(conn, ~p"/")
    guest_id = get_session(conn, :guest_id)
    assert is_binary(guest_id)
    conn = conn |> recycle() |> get(~p"/")
    assert get_session(conn, :guest_id) == guest_id
  end
end
