defmodule QueuePartyWeb.PageCopyLiveTest do
  use QueuePartyWeb.ConnCase
  import Phoenix.LiveViewTest
  alias QueueParty.Rooms

  test "homepage uses a direct headline without the numbered slogan strip", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    assert has_element?(view, "#home-title", "Watch")
    assert has_element?(view, "#home-title em", "together.")
    assert has_element?(view, "#home-description", "Add YouTube links to a shared queue.")
    refute has_element?(view, ".feature-strip")
    assert has_element?(view, "#create-room")
    assert has_element?(view, "#join-room")
  end

  test "host panel and room footer omit promotional copy while keeping controls", %{conn: conn} do
    {:ok, room} = Rooms.create_room()
    {:ok, view, _} = live(conn, ~p"/room/#{room.code}?host=#{room.host_token}")
    view |> element("#toggle-host-controls") |> render_click()
    assert has_element?(view, "#host-controls[aria-label='Host controls']:not([hidden])")
    refute has_element?(view, "#host-controls-title")
    refute has_element?(view, ".host-controls-heading p")
    refute has_element?(view, "#room-settings > div > p")
    refute has_element?(view, "footer", "Everyone’s a DJ.")
    assert has_element?(view, "#close-host-controls")
    assert has_element?(view, "#playback-settings")
    assert has_element?(view, "#skip-settings")
    assert has_element?(view, "#transfer-host-form")
    assert has_element?(view, "#playlist-form")
  end
end
