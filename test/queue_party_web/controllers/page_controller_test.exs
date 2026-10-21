defmodule QueuePartyWeb.PageControllerTest do
  use QueuePartyWeb.ConnCase
  import Phoenix.LiveViewTest

  test "GET /", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#create-room")
    assert has_element?(view, "#join-room")
  end
end
