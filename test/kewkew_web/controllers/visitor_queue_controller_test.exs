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
    organization = create_organization_fixture()

    location =
      Ash.create!(
        Kewkew.Business.Location,
        %{name: "Riverside Community Hub", organization_id: organization.id},
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
    assert LazyHTML.query_by_id(document, "visitor-ticket-status") |> LazyHTML.text() =~ "Waiting"

    assert LazyHTML.query_by_id(document, "visitor-ticket-position") |> LazyHTML.text() =~
             "1 in line"

    assert LazyHTML.text(document) =~ "Food support"
    assert LazyHTML.text(document) =~ "Riverside Community Hub"
    assert LazyHTML.query_by_id(document, "copy-visitor-tracking-link")

    [tracking_url] =
      LazyHTML.query_by_id(document, "visitor-tracking-link") |> LazyHTML.attribute("value")

    assert String.ends_with?(tracking_url, tracking_path)

    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]

    refreshed_conn = get(recycle(conn), tracking_path)
    refreshed_document = refreshed_conn |> html_response(200) |> LazyHTML.from_document()

    assert LazyHTML.query_by_id(refreshed_document, "visitor-ticket-number") |> LazyHTML.text() =~
             "1"
  end

  test "successful visitor joins broadcast a minimal session update only after success" do
    queue = create_queue_fixture(max_active_tickets: 1)
    session = latest_session(queue)
    :ok = Kewkew.Queues.Updates.subscribe(session.id)

    assert {:ok, _join} =
             Kewkew.Queues.VisitorJoin.join_anonymous(queue.public_slug, new_attempt_token())

    assert_receive {:queue_session_updated, session_id}
    assert session_id == session.id

    assert {:error, :full} =
             Kewkew.Queues.VisitorJoin.join_anonymous(queue.public_slug, new_attempt_token())

    refute_receive {:queue_session_updated, ^session_id}
  end

  test "ticket page shows persisted position among active tickets", %{conn: conn} do
    queue = create_queue_fixture()
    first_token = new_attempt_token()
    second_token = new_attempt_token()

    assert {:ok, _first_join} =
             Kewkew.Queues.VisitorJoin.join_anonymous(queue.public_slug, first_token)

    assert {:ok, _second_join} =
             Kewkew.Queues.VisitorJoin.join_anonymous(queue.public_slug, second_token)

    conn = get(conn, "/t/#{second_token}")
    document = conn |> html_response(200) |> LazyHTML.from_document()

    assert LazyHTML.query_by_id(document, "visitor-ticket-position") |> LazyHTML.text() =~
             "2 in line"
  end

  test "visitor can cancel a waiting ticket and repeat the request safely", %{conn: conn} do
    queue = create_queue_fixture()
    token = new_attempt_token()
    assert {:ok, join} = Kewkew.Queues.VisitorJoin.join_anonymous(queue.public_slug, token)
    second_token = new_attempt_token()

    assert {:ok, _second_join} =
             Kewkew.Queues.VisitorJoin.join_anonymous(queue.public_slug, second_token)

    session = latest_session(queue)
    session_id = session.id
    :ok = Kewkew.Queues.Updates.subscribe(session.id)

    page = get(conn, "/t/#{token}")
    page_document = page |> html_response(200) |> LazyHTML.from_document()
    assert LazyHTML.query_by_id(page_document, "visitor-cancel-ticket")

    cancel_conn = post(recycle(page), "/t/#{token}/cancel")
    assert redirected_to(cancel_conn) == "/t/#{token}"
    assert_receive {:queue_session_updated, ^session_id}

    cancelled_page = get(recycle(cancel_conn), "/t/#{token}")
    cancelled_document = cancelled_page |> html_response(200) |> LazyHTML.from_document()

    assert LazyHTML.query_by_id(cancelled_document, "visitor-cancel-ticket")
           |> LazyHTML.attribute("id") == []

    assert LazyHTML.query_by_id(cancelled_document, "visitor-ticket-status")
           |> LazyHTML.text() =~ "You left this queue"

    ticket = Kewkew.Repo.get!(Kewkew.Queues.Ticket, join.ticket.id)
    assert ticket.status == :cancelled
    assert ticket.cancelled_at
    assert ticket_event_count(ticket.id, :cancelled) == 1

    second_page = get(recycle(cancelled_page), "/t/#{second_token}")
    second_document = second_page |> html_response(200) |> LazyHTML.from_document()

    assert LazyHTML.query_by_id(second_document, "visitor-ticket-position")
           |> LazyHTML.text() =~ "1 in line"

    repeated_conn = post(recycle(cancelled_page), "/t/#{token}/cancel")
    assert redirected_to(repeated_conn) == "/t/#{token}"
    refute_receive {:queue_session_updated, _session_id}
    assert ticket_event_count(ticket.id, :cancelled) == 1
  end

  test "visitor cannot cancel after being called and gets the policy explanation", %{conn: conn} do
    queue = create_queue_fixture()
    token = new_attempt_token()
    assert {:ok, join} = Kewkew.Queues.VisitorJoin.join_anonymous(queue.public_slug, token)

    join.ticket
    |> Ecto.Changeset.change(status: :called)
    |> Kewkew.Repo.update!()

    page = get(conn, "/t/#{token}")
    document = page |> html_response(200) |> LazyHTML.from_document()

    assert LazyHTML.query_by_id(document, "visitor-cancel-ticket")
           |> LazyHTML.attribute("id") == []

    assert LazyHTML.query_by_id(document, "visitor-cancellation-policy")

    response = post(recycle(page), "/t/#{token}/cancel")
    assert redirected_to(response) == "/t/#{token}"
    assert Kewkew.Repo.get!(Kewkew.Queues.Ticket, join.ticket.id).status == :called
  end

  test "ticket status endpoint returns only the visitor's current status and position", %{
    conn: conn
  } do
    queue = create_queue_fixture()
    first_token = new_attempt_token()
    second_token = new_attempt_token()

    assert {:ok, _first_join} =
             Kewkew.Queues.VisitorJoin.join_anonymous(queue.public_slug, first_token)

    assert {:ok, second_join} =
             Kewkew.Queues.VisitorJoin.join_anonymous(queue.public_slug, second_token)

    second_join.ticket
    |> Ecto.Changeset.change(status: :called)
    |> Kewkew.Repo.update!()

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get("/t/#{second_token}/status")

    response = json_response(conn, 200)

    assert response["status"] == "called"
    assert response["status_label"] == "Your number has been called"
    assert response["position"] == 2
    refute Map.has_key?(response, "first_name")
    refute Map.has_key?(response, "tracking_token")
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]

    second_join.ticket
    |> Ecto.Changeset.change(status: :serving)
    |> Kewkew.Repo.update!()

    serving_response =
      conn
      |> recycle()
      |> put_req_header("accept", "application/json")
      |> get("/t/#{second_token}/status")
      |> json_response(200)

    assert serving_response["status"] == "serving"
    assert serving_response["status_label"] == "Being served"
    assert serving_response["position"] == 2

    second_join.ticket
    |> Ecto.Changeset.change(status: :completed, completed_at: DateTime.utc_now())
    |> Kewkew.Repo.update!()

    completed_response =
      conn
      |> recycle()
      |> put_req_header("accept", "application/json")
      |> get("/t/#{second_token}/status")
      |> json_response(200)

    assert completed_response["status"] == "completed"
    assert completed_response["status_label"] == "Service complete"
    assert is_nil(completed_response["position"])
  end

  test "ticket status endpoint shows a skipped ticket as inactive", %{conn: conn} do
    queue = create_queue_fixture()
    token = new_attempt_token()
    assert {:ok, join} = Kewkew.Queues.VisitorJoin.join_anonymous(queue.public_slug, token)

    join.ticket
    |> Ecto.Changeset.change(status: :no_show)
    |> Kewkew.Repo.update!()

    response = get(conn, "/t/#{token}/status") |> json_response(200)

    assert response["status"] == "no_show"
    assert response["status_label"] == "Marked as not present"
    assert is_nil(response["position"])
  end

  test "malformed or unknown tracking tokens show a generic unavailable page", %{conn: conn} do
    conn = get(conn, "/t/not-a-valid-token")
    response = html_response(conn, 404)
    text = response |> LazyHTML.from_document() |> LazyHTML.text()

    assert text =~ "This queue link isn’t available"
    refute text =~ "Your ticket number"
    refute text =~ "Riverside Community Hub"
  end

  test "revoked tracking tokens show the same generic unavailable page", %{conn: conn} do
    queue = create_queue_fixture()
    token = new_attempt_token()
    assert {:ok, _join} = Kewkew.Queues.VisitorJoin.join_anonymous(queue.public_slug, token)
    revoke_tracking_token(token)

    conn = get(conn, "/t/#{token}")
    response = html_response(conn, 404)
    text = response |> LazyHTML.from_document() |> LazyHTML.text()

    assert text =~ "This queue link isn’t available"
    refute text =~ "Your ticket number"
  end

  test "expired tracking tokens show the same generic unavailable page", %{conn: conn} do
    queue = create_queue_fixture()
    token = new_attempt_token()
    assert {:ok, _join} = Kewkew.Queues.VisitorJoin.join_anonymous(queue.public_slug, token)
    expire_tracking_token(token)

    conn = get(conn, "/t/#{token}")
    response = html_response(conn, 404)
    text = response |> LazyHTML.from_document() |> LazyHTML.text()

    assert text =~ "This queue link isn’t available"
    refute text =~ "Your ticket number"
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

  test "name-required queue displays first and last name fields", %{conn: conn} do
    queue = create_queue_fixture(identity_policy: :name_required)

    conn = get(conn, "/q/#{queue.public_slug}/join")
    document = conn |> html_response(200) |> LazyHTML.from_document()

    assert LazyHTML.query_by_id(document, "visitor-join-name-required")

    assert LazyHTML.query(document, "#visitor-join-form input[name='join[first_name]']")
           |> LazyHTML.attribute("name") == ["join[first_name]"]

    assert LazyHTML.query(document, "#visitor-join-form input[name='join[last_name]']")
           |> LazyHTML.attribute("name") == ["join[last_name]"]
  end

  test "name-required join trims names and does not repeat them on the ticket page", %{conn: conn} do
    queue = create_queue_fixture(identity_policy: :name_required)
    attempt_token = new_attempt_token()

    assert {:ok, join} =
             Kewkew.Queues.VisitorJoin.join_visitor(queue.public_slug, attempt_token, %{
               "first_name" => "  Ada ",
               "last_name" => " Lovelace  "
             })

    assert join.ticket.first_name == "Ada"
    assert join.ticket.last_name == "Lovelace"

    conn = get(conn, "/t/#{attempt_token}")
    document = conn |> html_response(200) |> LazyHTML.from_document()
    text = LazyHTML.text(document)

    assert text =~ "Your ticket number"
    refute text =~ "Ada"
    refute text =~ "Lovelace"
  end

  test "name-required join rejects missing first or last names without a ticket" do
    queue = create_queue_fixture(identity_policy: :name_required)

    assert {:error, :first_name_required} =
             Kewkew.Queues.VisitorJoin.join_visitor(queue.public_slug, new_attempt_token(), %{
               "first_name" => "  ",
               "last_name" => "Lovelace"
             })

    assert {:error, :last_name_required} =
             Kewkew.Queues.VisitorJoin.join_visitor(queue.public_slug, new_attempt_token(), %{
               "first_name" => "Ada",
               "last_name" => ""
             })

    session = latest_session(queue)
    assert count_tickets(session.id) == 0
  end

  test "name-required form keeps valid input and identifies a missing field", %{conn: conn} do
    queue = create_queue_fixture(identity_policy: :name_required)
    conn = get(conn, "/q/#{queue.public_slug}/join")
    document = conn |> html_response(200) |> LazyHTML.from_document()

    [attempt_token] =
      document
      |> LazyHTML.query("#visitor-join-form input[name='join[attempt_token]']")
      |> LazyHTML.attribute("value")

    conn =
      post(conn, "/q/#{queue.public_slug}/join", %{
        "join" => %{
          "attempt_token" => attempt_token,
          "first_name" => "",
          "last_name" => "Lovelace"
        }
      })

    document = conn |> html_response(200) |> LazyHTML.from_document()

    assert LazyHTML.query_by_id(document, "visitor-first-name-error")

    assert LazyHTML.query(document, "#visitor-join-form input[name='join[last_name]']")
           |> LazyHTML.attribute("value") == ["Lovelace"]
  end

  defp create_queue_fixture(opts \\ []) do
    organization = create_organization_fixture()

    location =
      Ash.create!(
        Kewkew.Business.Location,
        %{name: "Riverside Community Hub", organization_id: organization.id},
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

  defp create_organization_fixture do
    Ash.create!(
      Kewkew.Business.Organization,
      %{name: "Test organization"},
      domain: Kewkew.Business,
      authorize?: false
    )
  end

  defp new_attempt_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp latest_session(queue) do
    Ash.read_one!(
      Ash.Query.for_read(Kewkew.Queues.QueueSession, :latest_for_queue, %{queue_id: queue.id}),
      domain: Kewkew.Queues
    )
  end

  defp count_tickets(session_id) do
    Kewkew.Queues.Ticket
    |> Ash.Query.filter(queue_session_id == ^session_id)
    |> Ash.count!(domain: Kewkew.Queues)
  end

  defp revoke_tracking_token(token) do
    credential = tracking_credential(token)

    credential
    |> Ecto.Changeset.change(revoked_at: DateTime.utc_now())
    |> Kewkew.Repo.update!()
  end

  defp expire_tracking_token(token) do
    credential = tracking_credential(token)

    credential
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1, :second))
    |> Kewkew.Repo.update!()
  end

  defp tracking_credential(token) do
    digest = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

    Ash.read_one!(
      Ash.Query.filter(Kewkew.Queues.TrackingCredential, token_digest == ^digest),
      domain: Kewkew.Queues
    )
  end

  defp ticket_event_count(ticket_id, to_status) do
    Kewkew.Queues.TicketEvent
    |> Ash.Query.filter(ticket_id == ^ticket_id and to_status == ^to_status)
    |> Ash.count!(domain: Kewkew.Queues)
  end
end
