defmodule KewkewWeb.VisitorQueueControllerTest do
  use KewkewWeb.ConnCase

  test "shows the queue, service, location, and open state for a valid public link", %{conn: conn} do
    queue = create_queue_fixture()

    conn = get(conn, "/q/#{queue.public_slug}")

    response = html_response(conn, 200)
    document = LazyHTML.from_document(response)

    assert document |> LazyHTML.query_by_id("visitor-queue-details") |> LazyHTML.text() =~
             "Community food support"

    assert document
           |> LazyHTML.query_by_id("visitor-service-name")
           |> LazyHTML.text()
           |> String.trim() == "Food support"

    assert document |> LazyHTML.query_by_id("visitor-queue-status") |> LazyHTML.text() =~
             "Open now"
  end

  test "shows a generic unavailable page for an unknown queue link", %{conn: conn} do
    conn = get(conn, "/q/not-a-real-queue")

    response = html_response(conn, 404)
    document = LazyHTML.from_document(response)
    text = LazyHTML.text(document)

    assert text =~ "This queue link isn’t available"
    refute text =~ "Community food support"
    refute text =~ "Riverside Community Hub"
  end

  test "shows availability when a queue has no current session", %{conn: conn} do
    queue = create_queue_fixture(session_status: nil)

    conn = get(conn, "/q/#{queue.public_slug}")

    response = html_response(conn, 200)
    document = LazyHTML.from_document(response)

    assert document |> LazyHTML.query_by_id("visitor-queue-status") |> LazyHTML.text() =~
             "Not accepting visitors"
  end

  defp create_queue_fixture(opts \\ []) do
    location =
      Ash.create!(
        Kewkew.Business.Location,
        %{name: "Riverside Community Hub"},
        domain: Kewkew.Business
      )

    service =
      Ash.create!(
        Kewkew.Business.Service,
        %{name: "Food support", location_id: location.id},
        domain: Kewkew.Business
      )

    queue =
      Ash.create!(
        Kewkew.Queues.Queue,
        %{
          name: "Community food support",
          public_slug: "riverside-food-#{System.unique_integer([:positive])}",
          location_id: location.id,
          service_id: service.id
        },
        domain: Kewkew.Queues
      )

    if session_status = Keyword.get(opts, :session_status, :open) do
      Ash.create!(
        Kewkew.Queues.QueueSession,
        %{queue_id: queue.id, status: session_status},
        domain: Kewkew.Queues
      )
    end

    queue
  end
end
