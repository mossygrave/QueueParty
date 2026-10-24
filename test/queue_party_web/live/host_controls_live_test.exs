defmodule QueuePartyWeb.HostControlsLiveTest do
  use QueuePartyWeb.ConnCase
  import Phoenix.LiveViewTest
  alias QueueParty.Rooms

  setup do
    {:ok, room} = Rooms.create_room()

    {:ok, host, _} =
      live(
        init_test_session(build_conn(), %{guest_id: "controls-host"}),
        ~p"/room/#{room.code}?host=#{room.host_token}"
      )

    {:ok, guest, _} =
      live(init_test_session(build_conn(), %{guest_id: "controls-guest"}), ~p"/room/#{room.code}")

    %{room: room, host: host, guest: guest}
  end

  test "settings start collapsed and the host can open and close them", %{
    host: host,
    guest: guest
  } do
    assert has_element?(
             host,
             "#toggle-host-controls[aria-expanded=false][aria-controls=host-controls]"
           )

    assert has_element?(host, "#host-controls[hidden]")
    refute has_element?(host, "#host-controls[phx-window-keydown]")
    refute has_element?(guest, "#toggle-host-controls")
    refute has_element?(guest, "#host-controls")
    host |> element("#toggle-host-controls") |> render_click()
    assert has_element?(host, "#toggle-host-controls[aria-expanded=true]")
    assert has_element?(host, "#host-controls[phx-window-keydown][phx-key=Escape]")
    assert has_element?(host, "#host-controls:not([hidden]) #playback-settings")
    assert has_element?(host, "#host-controls #skip-settings")
    assert has_element?(host, "#host-controls #transfer-host-form")
    assert has_element?(host, "#host-controls #playlist-form")
    host |> element("#close-host-controls") |> render_click()
    assert has_element?(host, "#host-controls[hidden]")
    host |> element("#toggle-host-controls") |> render_click()
    host |> element("#toggle-host-controls") |> render_click()
    assert has_element?(host, "#host-controls[hidden]")
    render_hook(guest, "toggle_host_menu", %{})
    refute has_element?(guest, "#host-controls")
  end

  test "room updates preserve the panel state and closing leaves playback and settings alone", %{
    room: room,
    host: host
  } do
    host |> element("#toggle-host-controls") |> render_click()
    host |> form("#playback-settings", playback_mode: "everyone") |> render_change()
    {:ok, first} = Rooms.add_item(room.code, "M7lc1UVf-VE", "Current")
    assert has_element?(host, "#host-controls:not([hidden])")
    Rooms.update_playback(room.code, room.host_token, first.id, "paused", 42)
    before = Rooms.get_room(room.code)
    render_hook(host, "close_host_menu", %{})
    assert has_element?(host, "#host-controls[hidden]")
    assert Rooms.get_room(room.code).playback == before.playback
    Rooms.add_item(room.code, "M7lc1UVf-VE", "Next")
    assert has_element?(host, "#host-controls[hidden]")
    assert has_element?(host, "#skip-video")
    assert has_element?(host, "#queue .queue-drag-handle")
    host |> element("#toggle-host-controls") |> render_click()
    assert has_element?(host, "#playback-mode option[value=everyone][selected]")
  end

  test "playlist imports finish even when the panel is closed", %{host: host} do
    host |> element("#toggle-host-controls") |> render_click()

    host
    |> form("#playlist-form", url: "https://www.youtube.com/playlist?list=PLQueuePartyDemo")
    |> render_submit()

    host |> element("#close-host-controls") |> render_click()
    render_async(host)
    assert has_element?(host, "#host-controls[hidden]")
    assert has_element?(host, "#playlist-title", "Party playlist")
    host |> element("#toggle-host-controls") |> render_click()
    assert has_element?(host, "#remove-playlist")
    assert has_element?(host, "#playlist-repeat")
  end

  test "host transfer removes the old panel and gives the new host a collapsed panel", %{
    room: room,
    host: host,
    guest: guest
  } do
    host |> element("#toggle-host-controls") |> render_click()
    Rooms.transfer_host(room.code, room.host_token, "controls-guest")
    refute has_element?(host, "#host-controls")
    assert has_element?(guest, "#host-controls[hidden]")
    guest |> element("#toggle-host-controls") |> render_click()
    assert has_element?(guest, "#host-controls:not([hidden])")
  end
end
