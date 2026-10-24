defmodule QueueParty.QueueReorderTest do
  use ExUnit.Case, async: true
  alias QueueParty.Rooms

  defp setup_queue do
    {:ok, room} = Rooms.create_room()
    {:ok, current} = Rooms.add_item(room.code, "M7lc1UVf-VE", "Current")

    items =
      for name <- ["A", "B", "C"], do: elem(Rooms.add_item(room.code, "M7lc1UVf-VE", name), 1)

    {room, current, items}
  end

  test "host moves requests to the start, middle and end without changing playback" do
    {room, current, [a, b, c]} = setup_queue()
    Rooms.update_playback(room.code, room.host_token, current.id, "paused", 42)
    before = Rooms.get_room(room.code)
    assert {:ok, moved} = Rooms.move_item(room.code, room.host_token, c.id, a.id)
    assert Enum.map(moved.items, & &1.id) == [c.id, a.id, b.id]
    assert moved.now_playing == before.now_playing
    assert moved.playback == before.playback
    assert moved.skip_votes == before.skip_votes
    assert {:ok, moved} = Rooms.move_item(room.code, room.host_token, c.id, b.id)
    assert Enum.map(moved.items, & &1.id) == [a.id, c.id, b.id]
    assert {:ok, moved} = Rooms.move_item(room.code, room.host_token, a.id, nil)
    assert Enum.map(moved.items, & &1.id) == [c.id, b.id, a.id]
    Rooms.skip(room.code, room.host_token)
    assert Rooms.get_room(room.code).now_playing.id == c.id
  end

  test "moving one item preserves additions and rejects stale, current or malformed IDs" do
    {room, current, [a, b, c]} = setup_queue()
    {:ok, extra} = Rooms.add_item(room.code, "M7lc1UVf-VE", "Added during drag")
    {:ok, moved} = Rooms.move_item(room.code, room.host_token, c.id, a.id)
    assert Enum.map(moved.items, & &1.id) == [c.id, a.id, b.id, extra.id]
    Rooms.remove_item(room.code, b.id, room.host_token)
    before = Rooms.get_room(room.code)

    for {id, anchor} <- [
          {b.id, a.id},
          {a.id, b.id},
          {current.id, a.id},
          {a.id, a.id},
          {nil, nil},
          {[], %{}}
        ] do
      assert {:error, :stale_queue} = Rooms.move_item(room.code, room.host_token, id, anchor)
      assert Rooms.get_room(room.code) == before
    end
  end

  test "guests and missing rooms cannot reorder" do
    {room, _, [a, _, c]} = setup_queue()
    before = Rooms.get_room(room.code)

    for token <- [nil, "forged"] do
      assert {:error, :forbidden} = Rooms.move_item(room.code, token, c.id, a.id)
    end

    assert Rooms.get_room(room.code) == before
    assert {:error, :not_found} = Rooms.move_item("MISSING", room.host_token, c.id, a.id)
  end

  test "reordering leaves the background playlist cursor unchanged" do
    {room, _, [a, _, c]} = setup_queue()
    {:ok, marker} = Rooms.begin_playlist_import(room.code, room.host_token)

    {:ok, loaded} =
      Rooms.complete_playlist_import(room.code, room.host_token, marker, %{
        id: "PLQueuePartyDemo",
        title: "Playlist",
        url: "https://www.youtube.com/playlist?list=PLQueuePartyDemo",
        tracks: [%{youtube_id: "dQw4w9WgXcQ", title: "Background"}]
      })

    {:ok, moved} = Rooms.move_item(room.code, room.host_token, c.id, a.id)
    assert moved.playlist == loaded.playlist
  end
end
