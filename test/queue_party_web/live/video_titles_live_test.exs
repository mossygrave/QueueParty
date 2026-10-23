defmodule QueuePartyWeb.VideoTitlesLiveTest do
  use QueuePartyWeb.ConnCase
  import Phoenix.LiveViewTest
  alias QueueParty.Rooms

  test "titles update for host, guests, late joiners, and after queue advancement", %{conn: conn} do
    {:ok, room} = Rooms.create_room()
    {:ok, host, _} = live(conn, ~p"/room/#{room.code}?host=#{room.host_token}")
    {:ok, guest, _} = live(build_conn(), ~p"/room/#{room.code}")
    Rooms.subscribe(room.code)
    guest |> form("#add-video", url: "https://youtu.be/title000001") |> render_submit()

    assert_receive {:room_updated, %{now_playing: %{title: "First song & live performance 🎵"}}},
                   1_000

    assert has_element?(host, "#now-playing-title", "First song & live performance 🎵")
    assert has_element?(guest, "#now-playing-title", "First song & live performance 🎵")
    guest |> form("#add-video", url: "https://youtu.be/title000002") |> render_submit()
    assert_receive {:room_updated, %{items: [%{title: "Second song <not HTML>"}]}}, 1_000
    assert has_element?(host, "#queue .queue-copy strong", "Second song <not HTML>")
    assert has_element?(guest, "#queue .queue-copy strong", "Second song <not HTML>")
    {:ok, late_guest, _} = live(build_conn(), ~p"/room/#{room.code}")
    assert has_element?(late_guest, "#queue .queue-copy strong", "Second song <not HTML>")
    refute has_element?(guest, "#queue .queue-copy strong script")
    host |> element("#skip-video") |> render_click()
    assert has_element?(guest, "#now-playing-title", "Second song <not HTML>")
    assert has_element?(host, "#youtube-player[data-video-id='title000002']")
  end

  test "unavailable metadata leaves a playable video with its fallback label", %{conn: conn} do
    {:ok, room} = Rooms.create_room()
    {:ok, host, _} = live(conn, ~p"/room/#{room.code}?host=#{room.host_token}")
    host |> form("#add-video", url: "https://youtu.be/M7lc1UVf-VE") |> render_submit()

    assert has_element?(
             host,
             "#youtube-player[data-video-id='M7lc1UVf-VE'][data-playback-status='playing']"
           )

    assert has_element?(host, "#now-playing-title", "YouTube video M7lc1UVf-VE")
    refute has_element?(host, "#room-error")
  end
end
