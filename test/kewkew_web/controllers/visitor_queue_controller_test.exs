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

    assert document
           |> LazyHTML.query_by_id("visitor-join-queue")
           |> LazyHTML.attribute("disabled") == []
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

    assert document
           |> LazyHTML.query_by_id("visitor-join-queue")
           |> LazyHTML.attribute("disabled") != []
  end

  test "explains a paused queue and disables joining", %{conn: conn} do
    queue = create_queue_fixture(session_status: :paused)

    conn = get(conn, "/q/#{queue.public_slug}")

    document = conn |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query_by_id("visitor-queue-status") |> LazyHTML.text() =~
             "Temporarily paused"

    assert document |> LazyHTML.query_by_id("visitor-queue-availability") |> LazyHTML.text() =~
             "temporarily paused"

    assert document
           |> LazyHTML.query_by_id("visitor-join-queue")
           |> LazyHTML.attribute("disabled") != []
  end

  test "explains a closed queue and disables joining", %{conn: conn} do
    queue = create_queue_fixture(session_status: :closed)

    conn = get(conn, "/q/#{queue.public_slug}")

    document = conn |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query_by_id("visitor-queue-status") |> LazyHTML.text() =~
             "Not accepting visitors"

    assert document |> LazyHTML.query_by_id("visitor-queue-availability") |> LazyHTML.text() =~
             "currently closed"

    assert document
           |> LazyHTML.query_by_id("visitor-join-queue")
           |> LazyHTML.attribute("disabled") != []
  end

  test "lists location services and lets visitors choose only joinable queues", %{conn: conn} do
    location =
      Ash.create!(
        Kewkew.Business.Location,
        %{name: "Riverside Community Hub"},
        domain: Kewkew.Business
      )

    open_queue = create_location_queue(location, "Food support", :open)
    paused_queue = create_location_queue(location, "Housing advice", :paused)

    conn = get(conn, "/locations/#{location.id}/services")

    document = conn |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query_by_id("visitor-service-options") |> LazyHTML.text() =~
             "Food support"

    assert document |> LazyHTML.query_by_id("visitor-service-options") |> LazyHTML.text() =~
             "Housing advice"

    assert document
           |> LazyHTML.query_by_id("visitor-service-#{open_queue.public_slug}")
           |> LazyHTML.attribute("href") == ["/q/#{open_queue.public_slug}"]

    assert document
           |> LazyHTML.query_by_id("visitor-service-#{paused_queue.public_slug}")
           |> LazyHTML.attribute("aria-disabled") == ["true"]

    assert document
           |> LazyHTML.query_by_id("visitor-service-#{paused_queue.public_slug}")
           |> LazyHTML.attribute("href") == []
  end

  test "shows a generic unavailable page for an unknown location", %{conn: conn} do
    conn = get(conn, "/locations/not-a-location/services")

    response = html_response(conn, 404)
    document = LazyHTML.from_document(response)

    assert LazyHTML.text(document) =~ "This queue link isn’t available"
    refute LazyHTML.text(document) =~ "Riverside Community Hub"
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

  defp create_location_queue(location, service_name, session_status) do
    service =
      Ash.create!(
        Kewkew.Business.Service,
        %{name: service_name, location_id: location.id},
        domain: Kewkew.Business
      )

    queue =
      Ash.create!(
        Kewkew.Queues.Queue,
        %{
          name: "#{service_name} queue",
          public_slug: "service-#{System.unique_integer([:positive])}",
          location_id: location.id,
          service_id: service.id
        },
        domain: Kewkew.Queues
      )

    Ash.create!(
      Kewkew.Queues.QueueSession,
      %{queue_id: queue.id, status: session_status},
      domain: Kewkew.Queues
    )

    queue
  end
end
