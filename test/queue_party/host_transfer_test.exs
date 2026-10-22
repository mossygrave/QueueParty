defmodule QueueParty.HostTransferTest do
  use ExUnit.Case, async: true
  alias QueueParty.{Rooms, RoomClient}

  setup do
    {:ok, room} = Rooms.create_room()
    Rooms.subscribe(room.code)
    %{room: room}
  end

  defp join(room, guest_id, host_token \\ nil) do
    start_supervised!(
      {RoomClient, code: room.code, guest_id: guest_id, host_token: host_token, name: guest_id},
      id: make_ref()
    )
  end

  defp disconnect(pid, code) do
    drain_updates()
    ref = Process.monitor(pid)
    GenServer.stop(pid, :normal)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert_receive {:room_updated, %{code: ^code, host_status: "reconnecting"}}
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
    {_, marker} = room.host_timer
    send(Process.whereis(Rooms), {:host_grace_expired, room.code, marker})
    Rooms.get_room(room.code)
  end

  test "manual transfer preserves playback and invalidates all old host actions", %{room: room} do
    join(room, "host", room.host_token)
    join(room, "guest")
    {:ok, first} = Rooms.add_item(room.code, "dQw4w9WgXcQ", "A")
    {:ok, second} = Rooms.add_item(room.code, "M7lc1UVf-VE", "B")
    Rooms.update_playback(room.code, room.host_token, first.id, "paused", 42)
    Rooms.set_playback_mode(room.code, room.host_token, "everyone")
    Rooms.request_skip(room.code, first.id, "another-guest")

    assert {:error, :forbidden} = Rooms.transfer_host(room.code, "wrong", "guest")

    assert {:error, :guest_unavailable} =
             Rooms.transfer_host(room.code, room.host_token, "missing")

    assert {:ok, transferred} = Rooms.transfer_host(room.code, room.host_token, "guest")
    assert transferred.host_guest_id == "guest"
    assert transferred.now_playing.id == first.id
    assert transferred.playback.position == 42
    assert transferred.playback.status == "paused"
    assert transferred.playback_mode == "everyone"
    assert MapSet.size(transferred.skip_votes) == 1
    assert transferred.host_token != room.host_token
    assert {:error, :forbidden} = Rooms.skip(room.code, room.host_token)
    assert {:error, :forbidden} = Rooms.remove_item(room.code, second.id, room.host_token)
    assert {:error, :forbidden} = Rooms.finish(room.code, first.id, room.host_token)
    assert {:error, :forbidden} = Rooms.set_skip_threshold(room.code, room.host_token, 1)
    assert {:error, :forbidden} = Rooms.set_playback_mode(room.code, room.host_token, "host_only")

    assert {:error, :forbidden} =
             Rooms.update_playback(room.code, room.host_token, first.id, "playing", 0)

    assert {:error, :forbidden} = Rooms.transfer_host(room.code, room.host_token, "host")
    assert {:ok, _} = Rooms.skip(room.code, transferred.host_token)
    assert Rooms.get_room(room.code).now_playing.id == second.id
  end

  test "host returns during grace period and stale expiry cannot transfer", %{room: room} do
    host = join(room, "host", room.host_token)
    join(room, "guest")
    offline = disconnect(host, room.code)
    join(room, "host")
    drain_updates()
    restored = expire(offline)
    assert restored.host_guest_id == "host"
    assert restored.host_status == "online"
    assert restored.host_timer == nil
    assert restored.host_token == room.host_token
  end

  test "grace expiry elects the longest currently connected guest", %{room: room} do
    host = join(room, "host", room.host_token)
    join(room, "first")
    join(room, "second")
    offline = disconnect(host, room.code)
    promoted = expire(offline)
    assert promoted.host_guest_id == "first"
    assert promoted.host_status == "online"
    join(room, "host", room.host_token)
    assert Rooms.get_room(room.code).host_guest_id == "first"
  end

  test "one remaining host tab prevents host-disconnected status", %{room: room} do
    host = join(room, "host", room.host_token)
    join(room, "host")
    drain_updates()
    ref = Process.monitor(host)
    GenServer.stop(host, :normal)
    assert_receive {:DOWN, ^ref, :process, ^host, :normal}

    assert_receive {:room_updated, %{host_guest_id: "host", participants: participants}}
                   when map_size(participants) > 0

    room = Rooms.get_room(room.code)
    assert room.host_status == "online"
    assert room.host_timer == nil
  end

  test "a reconnected guest goes behind guests who stayed connected", %{room: room} do
    host = join(room, "host", room.host_token)
    first = join(room, "first")
    join(room, "second")
    drain_updates()
    GenServer.stop(first, :normal)
    assert_receive {:room_updated, %{host_status: "online"}}
    join(room, "first")
    offline = disconnect(host, room.code)
    assert expire(offline).host_guest_id == "second"
  end

  test "empty room waits and a later guest can take over after grace", %{room: room} do
    host = join(room, "host", room.host_token)
    offline = disconnect(host, room.code)
    assert expire(offline).host_status == "waiting"
    join(room, "late-guest")
    assert Rooms.get_room(room.code).host_guest_id == "late-guest"
    assert Rooms.get_room(room.code).host_status == "online"
  end
end
