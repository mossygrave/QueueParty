defmodule QueueParty.RoomCleanupTest do
  use ExUnit.Case, async: true
  alias QueueParty.{Rooms, RoomClient}

  setup do
    {:ok, room} = Rooms.create_room()
    Rooms.subscribe(room.code)
    %{room: room}
  end

  defp join(room, guest_id, host_token \\ nil) do
    start_supervised!(
      {RoomClient, code: room.code, guest_id: guest_id, host_token: host_token},
      id: make_ref()
    )
  end

  defp disconnect(pid, code) do
    drain_updates()
    ref = Process.monitor(pid)
    GenServer.stop(pid, :normal)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert_receive {:room_updated, %{code: ^code}}
    Rooms.get_room(code)
  end

  defp drain_updates do
    receive do
      {:room_updated, _} -> drain_updates()
    after
      0 -> :ok
    end
  end

  defp expire(room) do
    {_, marker} = room.empty_timer
    send(Process.whereis(Rooms), {:empty_room_expired, room.code, marker})
    Rooms.get_room(room.code)
  end

  test "never-joined rooms get a 15-minute timer and are deleted on expiry", %{room: room} do
    {timer, _marker} = room.empty_timer
    assert Process.read_timer(timer) in 1..900_000
    {:ok, _} = Rooms.add_item(room.code, "dQw4w9WgXcQ", "A")
    assert Rooms.get_room(room.code).empty_timer == room.empty_timer
    assert expire(room) == nil
    assert Process.read_timer(timer) == false
    assert {:error, :not_found} = Rooms.join_room(room.code, "guest", nil, "Guest")
    assert {:error, :not_found} = Rooms.add_item(room.code, "dQw4w9WgXcQ", "A")
  end

  test "only the last departing participant starts cleanup, independently of host grace", %{
    room: room
  } do
    host = join(room, "host", room.host_token)
    guest = join(room, "guest")
    host_left = disconnect(host, room.code)
    assert host_left.host_status == "reconnecting"
    assert host_left.empty_timer == nil
    empty = disconnect(guest, room.code)
    assert {timer, _} = empty.empty_timer
    {_, host_marker} = empty.host_timer
    send(Process.whereis(Rooms), {:host_grace_expired, room.code, host_marker})
    waiting = Rooms.get_room(room.code)
    assert waiting.host_status == "waiting"
    assert waiting.empty_timer == empty.empty_timer
    assert expire(empty) == nil
    assert Process.read_timer(timer) == false
  end

  test "returning cancels cleanup and preserves the room's contents", %{room: room} do
    host = join(room, "host", room.host_token)
    {:ok, first} = Rooms.add_item(room.code, "dQw4w9WgXcQ", "A")
    {:ok, second} = Rooms.add_item(room.code, "M7lc1UVf-VE", "B")
    Rooms.set_playback_mode(room.code, room.host_token, "everyone")
    Rooms.set_skip_threshold(room.code, room.host_token, 4)
    Rooms.update_playback(room.code, room.host_token, first.id, "paused", 42)
    Rooms.request_skip(room.code, first.id, "guest")
    empty = disconnect(host, room.code)
    join(room, "host")
    restored = Rooms.get_room(room.code)
    assert restored.empty_timer == nil
    assert restored.host_status == "online"
    assert restored.now_playing.id == first.id
    assert restored.items == [second]
    assert restored.playback.status == "paused"
    assert restored.playback.position == 42
    assert restored.playback_mode == "everyone"
    assert restored.skip_threshold == 4
    assert MapSet.member?(restored.skip_votes, "guest")
    {timer, _} = empty.empty_timer
    assert Process.read_timer(timer) == false
    assert expire(empty).host_guest_id == "host"
  end

  test "a new empty interval is protected from the previous interval's timer", %{room: room} do
    host = join(room, "host", room.host_token)
    first_empty = disconnect(host, room.code)
    returned = join(room, "host")
    second_empty = disconnect(returned, room.code)
    refute second_empty.empty_timer == first_empty.empty_timer
    assert expire(first_empty).empty_timer == second_empty.empty_timer
    assert expire(second_empty) == nil
  end

  test "closing one of several tabs does not start cleanup", %{room: room} do
    first = join(room, "host", room.host_token)
    second = join(room, "host")
    assert disconnect(first, room.code).empty_timer == nil
    assert {_timer, _marker} = disconnect(second, room.code).empty_timer
  end

  test "creation timer cannot remove a connected room", %{room: room} do
    join(room, "host", room.host_token)
    assert expire(room).empty_timer == nil
    assert Rooms.get_room(room.code).host_status == "online"
  end

  test "cleanup cancels host grace and stale messages after deletion are harmless", %{room: room} do
    host = join(room, "host", room.host_token)
    empty = disconnect(host, room.code)
    {host_timer, host_marker} = empty.host_timer
    assert expire(empty) == nil
    assert Process.read_timer(host_timer) == false
    send(Process.whereis(Rooms), {:host_grace_expired, room.code, host_marker})
    assert expire(empty) == nil
    {:ok, other} = Rooms.create_room()
    assert Rooms.get_room(other.code).code == other.code
  end
end
