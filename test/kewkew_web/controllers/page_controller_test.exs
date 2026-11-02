defmodule KewkewWeb.PageControllerTest do
  use KewkewWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    document = conn |> html_response(200) |> LazyHTML.from_document()

    assert LazyHTML.query_by_id(document, "landing-page")

    assert LazyHTML.query_by_id(document, "landing-hero-title")
           |> LazyHTML.text() =~ "Less waiting around. More life in line."

    assert LazyHTML.query_by_id(document, "features")
    assert LazyHTML.query_by_id(document, "how-it-works")
  end
end
