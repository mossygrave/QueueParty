defmodule QueueParty.RoomTitlesTest do
  use ExUnit.Case, async: true
  alias QueueParty.Rooms

  test "background lookup updates the current video without changing playback" do
    {:ok, room} = Rooms.create_room()
    Rooms.subscribe(room.code)
    {:ok, item} = Rooms.add_item(room.code, "title000001", "A")
    assert item.title == "YouTube video title000001"
    item_id = item.id

    assert_receive {:room_updated,
                    %{now_playing: %{id: ^item_id, title: "First song & live performance 🎵"}}},
                   1_000

    updated = Rooms.get_room(room.code)
    assert updated.playback.item_id == item.id
    assert updated.playback.status == "playing"
    assert updated.playback.revision == 1
  end

  test "background lookup updates a queued item and keeps the paused current video untouched" do
    {:ok, room} = Rooms.create_room()
    {:ok, first} = Rooms.add_item(room.code, "M7lc1UVf-VE", "A")
    Rooms.update_playback(room.code, room.host_token, first.id, "paused", 42)
    playback = Rooms.get_room(room.code).playback
    Rooms.subscribe(room.code)
    {:ok, second} = Rooms.add_item(room.code, "title000002", "B")
    second_id = second.id

    assert_receive {:room_updated,
                    %{items: [%{id: ^second_id, title: "Second song <not HTML>"}]}},
                   1_000

    assert Rooms.get_room(room.code).playback == playback
    assert Rooms.get_room(room.code).now_playing.id == first.id
  end

  test "late results never restore removed or finished videos, even with repeated YouTube IDs" do
    {:ok, room} = Rooms.create_room()
    {:ok, first} = Rooms.add_item(room.code, "M7lc1UVf-VE", "A")
    {:ok, second} = Rooms.add_item(room.code, "M7lc1UVf-VE", "B")
    Rooms.remove_item(room.code, second.id, room.host_token)
    assert :ignored = Rooms.set_item_title(room.code, second.id, "Removed")
    assert Rooms.get_room(room.code).now_playing.title == first.title
    Rooms.finish(room.code, first.id, room.host_token)
    assert :ignored = Rooms.set_item_title(room.code, first.id, "Finished")
    assert Rooms.get_room(room.code).now_playing == nil
    assert Rooms.get_room(room.code).items == []
  end

  test "metadata for deleted rooms is safely ignored" do
    {:ok, room} = Rooms.create_room()
    {:ok, item} = Rooms.add_item(room.code, "M7lc1UVf-VE", "A")
    {_, marker} = room.empty_timer
    send(Process.whereis(Rooms), {:empty_room_expired, room.code, marker})
    assert Rooms.get_room(room.code) == nil
    assert :ignored = Rooms.set_item_title(room.code, item.id, "Late title")
  end
end
