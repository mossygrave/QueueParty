defmodule QueuePartyWeb.PlaylistLayoutLiveTest do
  use QueuePartyWeb.ConnCase
  import Phoenix.LiveViewTest
  alias QueueParty.Rooms

  setup %{conn: conn} do
    {:ok, room} = Rooms.create_room()
    {:ok, host, _} = live(conn, ~p"/room/#{room.code}?host=#{room.host_token}")

    {:ok, guest, _} =
      live(init_test_session(build_conn(), %{guest_id: "layout-guest"}), ~p"/room/#{room.code}")

    %{room: room, host: host, guest: guest}
  end

  defp load(host) do
    host
    |> form("#playlist-form", url: "https://www.youtube.com/playlist?list=PLQueuePartyDemo")
    |> render_submit()

    render_async(host)
  end

  test "playlist sits below the player, collapsed, while people remain with Play next", %{
    host: host,
    guest: guest
  } do
    load(host)

    for view <- [host, guest] do
      assert has_element?(view, "#player-column > .player-panel + #background-playlist")
      assert has_element?(view, "#background-playlist #playlist-title", "Party playlist")
      assert has_element?(view, "#playlist-preview[hidden]")

      assert has_element?(
               view,
               "#toggle-playlist-preview[aria-expanded=false][aria-controls=playlist-preview]"
             )

      assert has_element?(view, ".queue-panel #room-people")
      refute has_element?(view, ".queue-panel #background-playlist")
    end
  end

  test "each viewer can expand independently without changing playback, and updates preserve their choice",
       %{room: room, host: host, guest: guest} do
    load(host)
    first = Rooms.get_room(room.code).now_playing
    Rooms.update_playback(room.code, room.host_token, first.id, "paused", 42)
    playback = Rooms.get_room(room.code).playback
    guest |> element("#toggle-playlist-preview") |> render_click()

    assert has_element?(
             guest,
             "#playlist-preview:not([hidden]) #playlist-tracks li",
             "Playlist B"
           )

    assert has_element?(guest, "#toggle-playlist-preview[aria-expanded=true]", "Hide tracks")
    assert has_element?(host, "#playlist-preview[hidden]")
    assert Rooms.get_room(room.code).playback == playback
    host |> form("#playlist-repeat-form", repeat: true) |> render_change()
    assert has_element?(guest, "#playlist-preview:not([hidden])")
    assert has_element?(host, "#playlist-preview[hidden]")
    host |> element("#skip-video") |> render_click()

    assert has_element?(
             guest,
             "#playlist-preview:not([hidden]) #playlist-tracks li",
             "Playlist A"
           )

    assert has_element?(host, "#playlist-preview[hidden]")
    guest |> element("#toggle-playlist-preview") |> render_click()
    assert has_element?(guest, "#playlist-preview[hidden]")
  end

  test "removing a playlist closes its preview and the next import starts collapsed", %{
    host: host,
    guest: guest
  } do
    assert has_element?(host, "#player-column #no-playlist")
    refute has_element?(host, "#toggle-playlist-preview")
    load(host)
    guest |> element("#toggle-playlist-preview") |> render_click()
    host |> element("#remove-playlist") |> render_click()
    assert has_element?(guest, "#playlist-preview[hidden]")
    assert has_element?(guest, "#player-column #no-playlist")
    refute has_element?(guest, "#toggle-playlist-preview")
    load(host)
    assert has_element?(guest, "#playlist-preview[hidden]")
    assert has_element?(guest, "#toggle-playlist-preview[aria-expanded=false]")
  end
end
