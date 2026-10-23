defmodule QueueParty.PlaylistQueueTest do
  use ExUnit.Case, async: true
  alias QueueParty.Rooms

  defp data(title \\ "Party") do
    %{
      id: "PLQueuePartyDemo",
      title: title,
      url: "https://www.youtube.com/playlist?list=PLQueuePartyDemo",
      tracks: [
        %{youtube_id: "M7lc1UVf-VE", title: "A"},
        %{youtube_id: "dQw4w9WgXcQ", title: "B"}
      ]
    }
  end

  defp load(room, playlist \\ data()) do
    {:ok, marker} = Rooms.begin_playlist_import(room.code, room.host_token)
    {:ok, updated} = Rooms.complete_playlist_import(room.code, room.host_token, marker, playlist)
    updated
  end

  test "requests are FIFO, never interrupt, and playlist resumes at its next song" do
    {:ok, room} = Rooms.create_room()
    playing = load(room)
    a = playing.now_playing
    assert a.title == "A"
    {:ok, x} = Rooms.add_item(room.code, "title000003", "X")
    {:ok, y} = Rooms.add_item(room.code, "title000004", "Y")
    assert Rooms.get_room(room.code).now_playing.id == a.id
    Rooms.finish(room.code, a.id)
    assert Rooms.get_room(room.code).now_playing.id == x.id
    Rooms.finish(room.code, x.id)
    assert Rooms.get_room(room.code).now_playing.id == y.id
    Rooms.finish(room.code, y.id)
    assert Rooms.get_room(room.code).now_playing.title == "B"
    Rooms.skip(room.code, room.host_token)
    assert Rooms.get_room(room.code).now_playing == nil
  end

  test "repeat restarts in order with fresh item IDs and stale ends cannot advance twice" do
    {:ok, room} = Rooms.create_room()
    a = load(room).now_playing
    Rooms.set_playlist_repeat(room.code, room.host_token, true)
    Rooms.finish(room.code, a.id)
    Rooms.skip(room.code, room.host_token)
    repeated = Rooms.get_room(room.code).now_playing
    assert repeated.title == "A"
    refute repeated.id == a.id
    Rooms.finish(room.code, a.id)
    assert Rooms.get_room(room.code).now_playing.id == repeated.id
    Rooms.set_playlist_repeat(room.code, room.host_token, false)
    Rooms.skip(room.code, room.host_token)
    Rooms.skip(room.code, room.host_token)
    assert Rooms.get_room(room.code).now_playing == nil
    Rooms.set_playlist_repeat(room.code, room.host_token, true)
    assert Rooms.get_room(room.code).now_playing.title == "A"
  end

  test "replacement and removal preserve current song, pause state, and requests" do
    {:ok, room} = Rooms.create_room()
    a = load(room).now_playing
    Rooms.update_playback(room.code, room.host_token, a.id, "paused", 42)
    {:ok, request} = Rooms.add_item(room.code, "title000003", "X")
    replacement = load(room, data("Replacement"))
    assert replacement.playback.status == "paused"
    assert replacement.playback.position == 42
    assert replacement.now_playing.id == a.id
    Rooms.remove_playlist(room.code, room.host_token)
    Rooms.finish(room.code, a.id)
    assert Rooms.get_room(room.code).now_playing.id == request.id
    assert Rooms.get_room(room.code).playlist == nil
  end

  test "host authorization and import markers protect replacement and removal" do
    {:ok, room} = Rooms.create_room()
    assert {:error, :forbidden} = Rooms.begin_playlist_import(room.code, "wrong")
    assert {:error, :forbidden} = Rooms.remove_playlist(room.code, "wrong")
    assert {:error, :forbidden} = Rooms.set_playlist_repeat(room.code, "wrong", true)
    {:ok, first} = Rooms.begin_playlist_import(room.code, room.host_token)
    {:ok, second} = Rooms.begin_playlist_import(room.code, room.host_token)

    assert {:error, :stale_import} =
             Rooms.complete_playlist_import(room.code, room.host_token, first, data())

    assert {:error, :forbidden} =
             Rooms.complete_playlist_import(room.code, "wrong", second, data())

    Rooms.remove_playlist(room.code, room.host_token)

    assert {:error, :stale_import} =
             Rooms.complete_playlist_import(room.code, room.host_token, second, data())

    assert Rooms.get_room(room.code).playlist == nil
  end

  test "unavailable tracks are removed from repeat and cannot create an endless error loop" do
    {:ok, room} = Rooms.create_room()
    a = load(room).now_playing
    Rooms.set_playlist_repeat(room.code, room.host_token, true)
    assert {:error, :forbidden} = Rooms.fail_playlist_item(room.code, "wrong", a.id)
    Rooms.fail_playlist_item(room.code, room.host_token, a.id)
    b = Rooms.get_room(room.code).now_playing
    assert b.title == "B"
    Rooms.fail_playlist_item(room.code, room.host_token, b.id)
    assert Rooms.get_room(room.code).now_playing == nil
    assert Rooms.get_room(room.code).playlist.tracks == []
    {:ok, request} = Rooms.add_item(room.code, "title000003", "X")
    assert Rooms.get_room(room.code).now_playing.id == request.id
  end

  test "skip votes advance into pending requests before the next playlist track" do
    {:ok, room} = Rooms.create_room()
    a = load(room).now_playing
    {:ok, request} = Rooms.add_item(room.code, "title000003", "X")
    Rooms.set_skip_threshold(room.code, room.host_token, 1)
    Rooms.request_skip(room.code, a.id, "guest")
    assert Rooms.get_room(room.code).now_playing.id == request.id
    assert MapSet.size(Rooms.get_room(room.code).skip_votes) == 0
  end

  test "host transfer preserves the playlist but invalidates an old host's pending import" do
    {:ok, room} = Rooms.create_room()

    start_supervised!(
      {QueueParty.RoomClient, code: room.code, guest_id: "host", host_token: room.host_token},
      id: :host
    )

    start_supervised!({QueueParty.RoomClient, code: room.code, guest_id: "guest"}, id: :guest)
    playing = load(room)
    {:ok, marker} = Rooms.begin_playlist_import(room.code, room.host_token)
    {:ok, transferred} = Rooms.transfer_host(room.code, room.host_token, "guest")
    assert transferred.playlist == playing.playlist

    assert {:error, :forbidden} =
             Rooms.complete_playlist_import(room.code, room.host_token, marker, data("Wrong"))

    assert Rooms.get_room(room.code).playlist.title == "Party"
    assert {:ok, _} = Rooms.set_playlist_repeat(room.code, transferred.host_token, true)
  end

  test "pending imports cannot restore expired rooms and invalid data is rejected" do
    {:ok, room} = Rooms.create_room()
    {:ok, marker} = Rooms.begin_playlist_import(room.code, room.host_token)

    assert {:error, :invalid_playlist} =
             Rooms.complete_playlist_import(room.code, room.host_token, marker, %{
               data()
               | tracks: []
             })

    assert {:error, :invalid_repeat} =
             Rooms.set_playlist_repeat(room.code, room.host_token, "true")

    {_, expiry} = room.empty_timer
    send(Process.whereis(Rooms), {:empty_room_expired, room.code, expiry})
    assert Rooms.get_room(room.code) == nil

    assert {:error, :not_found} =
             Rooms.complete_playlist_import(room.code, room.host_token, marker, data())

    assert Rooms.get_room(room.code) == nil
  end
end
