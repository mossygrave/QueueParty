defmodule QueuePartyWeb.PageControllerTest do
  use QueuePartyWeb.ConnCase
  import Phoenix.LiveViewTest

  test "GET /", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#create-room")
    assert has_element?(view, "#join-room")
  end

  test "the page uses the record favicon", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document
           |> LazyHTML.query("link[rel='icon'][type='image/svg+xml'][href='/images/record.svg']")
           |> Enum.count() == 1
  end

  test "the record favicon is served as SVG", %{conn: conn} do
    conn = get(conn, ~p"/images/record.svg")
    assert response(conn, 200) == File.read!("priv/static/images/record.svg")
    assert [content_type] = get_resp_header(conn, "content-type")
    assert content_type =~ "image/svg+xml"
  end
end
