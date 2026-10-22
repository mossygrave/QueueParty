defmodule QueueParty.AutostartTest do
  use ExUnit.Case, async: true
  alias QueueParty.Rooms

  test "first submission starts once and later submissions stay queued" do
    {:ok, room} = Rooms.create_room()
    Rooms.subscribe(room.code)
    {:ok, first} = Rooms.add_item(room.code, "dQw4w9WgXcQ", "A")
    first_id = first.id
    assert_receive {:room_updated, %{now_playing: %{id: ^first_id}, items: []}}
    started = Rooms.get_room(room.code)
    assert %{item_id: ^first_id, status: "playing", revision: 1} = started.playback
    assert started.playback.position == 0.0
    {:ok, second} = Rooms.add_item(room.code, "M7lc1UVf-VE", "B")
    queued = Rooms.get_room(room.code)
    assert queued.now_playing.id == first.id
    assert queued.items == [second]
    assert queued.playback == started.playback
  end

  test "new submission restarts an exhausted room after a finish or skip" do
    for ending <- [:finish, :skip] do
      {:ok, room} = Rooms.create_room()
      {:ok, first} = Rooms.add_item(room.code, "dQw4w9WgXcQ", "A")

      case ending do
        :finish -> Rooms.finish(room.code, first.id)
        :skip -> Rooms.skip(room.code, room.host_token)
      end

      assert Rooms.get_room(room.code).now_playing == nil
      {:ok, next} = Rooms.add_item(room.code, "M7lc1UVf-VE", "B")
      restarted = Rooms.get_room(room.code)
      assert restarted.now_playing.id == next.id
      assert restarted.playback.status == "playing"
      assert restarted.playback.position == 0.0
      assert restarted.items == []
    end
  end

  test "submissions never resume a paused song or disturb its skip votes" do
    {:ok, room} = Rooms.create_room()
    {:ok, first} = Rooms.add_item(room.code, "dQw4w9WgXcQ", "A")
    Rooms.update_playback(room.code, room.host_token, first.id, "paused", 42)
    Rooms.request_skip(room.code, first.id, "guest")
    {:ok, second} = Rooms.add_item(room.code, "M7lc1UVf-VE", "B")
    updated = Rooms.get_room(room.code)
    assert updated.now_playing.id == first.id
    assert updated.playback.status == "paused"
    assert updated.playback.position == 42
    assert updated.items == [second]
    assert MapSet.size(updated.skip_votes) == 1
  end

  test "simultaneous submissions start one video and keep the rest queued" do
    {:ok, room} = Rooms.create_room()

    items =
      Task.async_stream(
        1..8,
        fn number ->
          Rooms.add_item(room.code, "dQw4w9WgXcQ", "Guest #{number}")
        end,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, {:ok, item}} -> item end)

    updated = Rooms.get_room(room.code)
    assert updated.playback.revision == 1
    assert length(updated.items) == 7

    assert MapSet.new(Enum.map([updated.now_playing | updated.items], & &1.id)) ==
             MapSet.new(Enum.map(items, & &1.id))
  end
end
