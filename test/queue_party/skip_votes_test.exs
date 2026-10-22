defmodule QueueParty.SkipVotesTest do
  use ExUnit.Case, async: true
  alias QueueParty.Rooms

  setup do
    {:ok, room} = Rooms.create_room()
    {:ok, first} = Rooms.add_item(room.code, "dQw4w9WgXcQ", "A")
    {:ok, second} = Rooms.add_item(room.code, "M7lc1UVf-VE", "B")
    %{room: room, first: first, second: second}
  end

  test "distinct votes skip once at the threshold and clear for the next song", %{
    room: room,
    first: first,
    second: second
  } do
    for _ <- 1..2, do: Rooms.request_skip(room.code, first.id, "guest-a")
    assert MapSet.size(Rooms.get_room(room.code).skip_votes) == 1
    Rooms.request_skip(room.code, first.id, "guest-b")
    assert Rooms.get_room(room.code).now_playing.id == first.id
    Rooms.request_skip(room.code, first.id, "guest-c")
    assert Rooms.get_room(room.code).now_playing.id == second.id
    assert MapSet.size(Rooms.get_room(room.code).skip_votes) == 0
    assert {:error, :stale_item} = Rooms.request_skip(room.code, first.id, "guest-d")
    assert {:error, :stale_item} = Rooms.approve_skip(room.code, room.host_token, first.id)
    assert Rooms.get_room(room.code).now_playing.id == second.id
  end

  test "only authenticated host can approve or change the threshold", %{
    room: room,
    first: first,
    second: second
  } do
    Rooms.request_skip(room.code, first.id, "guest-a")
    assert {:error, :forbidden} = Rooms.approve_skip(room.code, "wrong", first.id)
    assert {:error, :forbidden} = Rooms.set_skip_threshold(room.code, "wrong", 1)

    for invalid <- [0, -1, 101, "2", 1.5] do
      assert {:error, :invalid_threshold} =
               Rooms.set_skip_threshold(room.code, room.host_token, invalid)
    end

    assert {:ok, updated} = Rooms.approve_skip(room.code, room.host_token, first.id)
    assert updated.now_playing.id == second.id
    assert MapSet.size(updated.skip_votes) == 0
  end

  test "lowering the threshold applies existing votes and final-track skips empty playback", %{
    room: room,
    first: first,
    second: second
  } do
    Rooms.request_skip(room.code, first.id, "guest-a")
    Rooms.request_skip(room.code, first.id, "guest-b")
    assert {:ok, updated} = Rooms.set_skip_threshold(room.code, room.host_token, 2)
    assert updated.now_playing.id == second.id
    Rooms.request_skip(room.code, second.id, "guest-a")
    Rooms.request_skip(room.code, second.id, "guest-b")
    assert Rooms.get_room(room.code).now_playing == nil
    assert Rooms.get_room(room.code).playback.status == "paused"
    assert {:error, :stale_item} = Rooms.request_skip(room.code, second.id, "guest-c")
    assert {:error, :invalid_guest} = Rooms.request_skip(room.code, second.id, nil)
  end

  test "natural advancement also resets votes", %{room: room, first: first} do
    Rooms.request_skip(room.code, first.id, "guest-a")
    Rooms.finish(room.code, first.id)
    assert MapSet.size(Rooms.get_room(room.code).skip_votes) == 0
  end

  test "simultaneous final votes cannot skip two songs", %{
    room: room,
    first: first,
    second: second
  } do
    Rooms.set_skip_threshold(room.code, room.host_token, 2)
    Rooms.request_skip(room.code, first.id, "guest-a")

    results =
      Task.async_stream(
        ["guest-b", "guest-c"],
        fn guest_id ->
          Rooms.request_skip(room.code, first.id, guest_id)
        end,
        timeout: :infinity
      )
      |> Enum.to_list()

    assert Enum.count(results, &match?({:ok, {:ok, _}}, &1)) == 1
    assert Enum.count(results, &match?({:ok, {:error, :stale_item}}, &1)) == 1
    assert Rooms.get_room(room.code).now_playing.id == second.id
    assert MapSet.size(Rooms.get_room(room.code).skip_votes) == 0
  end
end
