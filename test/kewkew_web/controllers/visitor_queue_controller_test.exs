defmodule KewkewWeb.VisitorQueueControllerTest do
  use KewkewWeb.ConnCase

  require Ash.Query

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

  test "anonymous queue join asks for no personal details", %{conn: conn} do
    queue = create_queue_fixture()

    conn = get(conn, "/q/#{queue.public_slug}/join")

    document = conn |> html_response(200) |> LazyHTML.from_document()

    assert LazyHTML.query_by_id(document, "visitor-join-form")
    assert LazyHTML.query_by_id(document, "visitor-confirm-join")
    assert LazyHTML.text(document) =~ "No name or contact details are needed"

    assert LazyHTML.query(document, "input[name='join[first_name]']")
           |> LazyHTML.attribute("name") == []

    assert LazyHTML.query(document, "input[name='join[last_name]']")
           |> LazyHTML.attribute("name") == []
  end

  test "anonymous join creates one ticket and returns its private tracking page", %{conn: conn} do
    queue = create_queue_fixture()
    attempt_token = new_attempt_token()

    assert {:ok, first_join} =
             Kewkew.Queues.VisitorJoin.join_anonymous(queue.public_slug, attempt_token)

    assert {:ok, repeated_join} =
             Kewkew.Queues.VisitorJoin.join_anonymous(queue.public_slug, attempt_token)

    assert first_join.ticket.id == repeated_join.ticket.id
    assert first_join.ticket.ticket_number == 1

    tracking_path = "/t/#{attempt_token}"
    conn = get(conn, tracking_path)

    document = conn |> html_response(200) |> LazyHTML.from_document()

    assert LazyHTML.query_by_id(document, "visitor-ticket")
    assert LazyHTML.query_by_id(document, "visitor-ticket-number") |> LazyHTML.text() =~ "1"
    assert LazyHTML.text(document) =~ "Food support"
    assert LazyHTML.text(document) =~ "Riverside Community Hub"
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
  end

  test "submitting the visitor form redirects to the private ticket page", %{conn: conn} do
    queue = create_queue_fixture()
    conn = get(conn, "/q/#{queue.public_slug}/join")
    document = conn |> html_response(200) |> LazyHTML.from_document()

    [attempt_token] =
      document
      |> LazyHTML.query("#visitor-join-form input[name='join[attempt_token]']")
      |> LazyHTML.attribute("value")

    conn =
      post(conn, "/q/#{queue.public_slug}/join", %{
        "join" => %{"attempt_token" => attempt_token}
      })

    assert redirected_to(conn) == "/t/#{attempt_token}"
  end

  test "join rejects name-required, paused, and full queues" do
    name_required_queue = create_queue_fixture(identity_policy: :name_required)

    assert {:error, :name_required} =
             Kewkew.Queues.VisitorJoin.join_anonymous(
               name_required_queue.public_slug,
               new_attempt_token()
             )

    paused_queue = create_queue_fixture(session_status: :paused)

    assert {:error, :unavailable} =
             Kewkew.Queues.VisitorJoin.join_anonymous(
               paused_queue.public_slug,
               new_attempt_token()
             )

    full_queue = create_queue_fixture(max_active_tickets: 1)

    assert {:ok, _join} =
             Kewkew.Queues.VisitorJoin.join_anonymous(full_queue.public_slug, new_attempt_token())

    assert {:error, :full} =
             Kewkew.Queues.VisitorJoin.join_anonymous(full_queue.public_slug, new_attempt_token())
  end

  test "name-required queue does not show anonymous join controls", %{conn: conn} do
    queue = create_queue_fixture(identity_policy: :name_required)

    conn = get(conn, "/q/#{queue.public_slug}/join")
    document = conn |> html_response(200) |> LazyHTML.from_document()

    assert LazyHTML.query_by_id(document, "visitor-join-name-required")
    assert LazyHTML.query_by_id(document, "visitor-join-message")

    assert LazyHTML.query(document, "form#visitor-join-form")
           |> LazyHTML.attribute("id") == []
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
          service_id: service.id,
          identity_policy: Keyword.get(opts, :identity_policy, :anonymous),
          max_active_tickets: Keyword.get(opts, :max_active_tickets)
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

  defp new_attempt_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
