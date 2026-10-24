defmodule QueuePartyWeb.QueueReorderLiveTest do
  use QueuePartyWeb.ConnCase
  import Phoenix.LiveViewTest
  alias QueueParty.Rooms

  defp queue_positions(view, ids) do
    Enum.with_index(ids, 1)
    |> Enum.each(fn {id, position} ->
      assert has_element?(
               view,
               "#items-#{id}:nth-child(#{position}) .queue-number",
               to_string(position)
             )
    end)
  end

  test "host order is synchronized to guests and played next", %{conn: conn} do
    {:ok, room} = Rooms.create_room()
    {:ok, current} = Rooms.add_item(room.code, "M7lc1UVf-VE", "Current")
    {:ok, a} = Rooms.add_item(room.code, "M7lc1UVf-VE", "A")
    {:ok, b} = Rooms.add_item(room.code, "M7lc1UVf-VE", "B")
    {:ok, host, _} = live(conn, ~p"/room/#{room.code}?host=#{room.host_token}")
    {:ok, guest, _} = live(build_conn(), ~p"/room/#{room.code}")
    assert has_element?(host, "#reorder-#{b.id}")
    refute has_element?(guest, ".queue-drag-handle")
    assert has_element?(host, "#queue[data-reorder-enabled=true]")
    render_hook(host, "move_queue_item", %{id: b.id, before_id: a.id})
    queue_positions(host, [b.id, a.id])
    queue_positions(guest, [b.id, a.id])
    assert has_element?(host, "#youtube-player[data-item-id='#{current.id}']")
    {:ok, late, _} = live(build_conn(), ~p"/room/#{room.code}")
    queue_positions(late, [b.id, a.id])
    host |> element("#skip-video") |> render_click()
    assert has_element?(host, "#youtube-player[data-item-id='#{b.id}']")
  end

  test "forged guest moves and stale drops leave the queue intact", %{conn: conn} do
    {:ok, room} = Rooms.create_room()
    Rooms.add_item(room.code, "M7lc1UVf-VE", "Current")
    {:ok, a} = Rooms.add_item(room.code, "M7lc1UVf-VE", "A")
    {:ok, b} = Rooms.add_item(room.code, "M7lc1UVf-VE", "B")
    {:ok, host, _} = live(conn, ~p"/room/#{room.code}?host=#{room.host_token}")
    {:ok, guest, _} = live(build_conn(), ~p"/room/#{room.code}")
    render_hook(guest, "move_queue_item", %{id: b.id, before_id: a.id})
    queue_positions(host, [a.id, b.id])
    render_hook(host, "move_queue_item", %{id: b.id, before_id: "removed"})
    queue_positions(host, [a.id, b.id])
  end

  test "controls and authorization follow host transfer", %{conn: conn} do
    {:ok, room} = Rooms.create_room()
    Rooms.add_item(room.code, "M7lc1UVf-VE", "Current")
    {:ok, a} = Rooms.add_item(room.code, "M7lc1UVf-VE", "A")
    {:ok, b} = Rooms.add_item(room.code, "M7lc1UVf-VE", "B")
    {:ok, host, _} = live(conn, ~p"/room/#{room.code}?host=#{room.host_token}")
    {:ok, guest, _} = live(build_conn(), ~p"/room/#{room.code}")
    [candidate] = Rooms.connected_guests(Rooms.get_room(room.code))
    {:ok, _} = Rooms.transfer_host(room.code, room.host_token, candidate.id)
    refute has_element?(host, ".queue-drag-handle")
    assert has_element?(guest, "#reorder-#{b.id}")
    assert {:error, :forbidden} = Rooms.move_item(room.code, room.host_token, b.id, a.id)
    render_hook(host, "move_queue_item", %{id: b.id, before_id: a.id})
    queue_positions(guest, [a.id, b.id])
    render_hook(guest, "move_queue_item", %{id: b.id, before_id: a.id})
    queue_positions(host, [b.id, a.id])
  end
end
