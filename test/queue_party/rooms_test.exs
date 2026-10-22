defmodule QueueParty.RoomsTest do
  use ExUnit.Case, async: true

  alias QueueParty.Rooms

  test "room settings and playback reports authenticate the host at the state boundary" do
    {:ok, room} = Rooms.create_room()
    {:ok, item} = Rooms.add_item(room.code, "dQw4w9WgXcQ", "A")
    Rooms.skip(room.code)

    assert {:error, :forbidden} = Rooms.set_playback_mode(room.code, "wrong-token", "everyone")

    assert {:error, :invalid_mode} =
             Rooms.set_playback_mode(room.code, room.host_token, "invalid")

    assert {:error, :forbidden} =
             Rooms.update_playback(room.code, "wrong-token", item.id, "paused", 10)

    assert {:error, :invalid_playback} =
             Rooms.update_playback(room.code, room.host_token, item.id, "playing", -1)

    assert {:error, :invalid_playback} =
             Rooms.update_playback(room.code, room.host_token, item.id, "invalid", 10)

    assert Rooms.get_room(room.code).playback_mode == "host_only"
  end

  test "the snapshot advances while playing and holds its position while paused or buffering" do
    {:ok, room} = Rooms.create_room()
    {:ok, item} = Rooms.add_item(room.code, "dQw4w9WgXcQ", "A")
    Rooms.skip(room.code)

    assert :ok = Rooms.update_playback(room.code, room.host_token, item.id, "playing", 35.0)
    assert Rooms.playback_snapshot(Rooms.get_room(room.code)).position >= 35.0

    for status <- ["paused", "buffering"] do
      assert :ok = Rooms.update_playback(room.code, room.host_token, item.id, status, 36.25)

      assert %{position: 36.25, status: ^status} =
               Rooms.playback_snapshot(Rooms.get_room(room.code))
    end
  end
end
