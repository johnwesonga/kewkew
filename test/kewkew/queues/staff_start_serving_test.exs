defmodule Kewkew.Queues.StaffStartServingTest do
  use Kewkew.DataCase

  require Ash.Query

  alias Kewkew.Queues.{StaffStartServing, Ticket, TicketEvent}

  test "starts a called ticket and records time and staff actor" do
    %{user: user, queue: queue, session: session} = staff_queue_fixture()
    ticket = create_ticket(session, :called)

    assert {:ok, serving} = StaffStartServing.start_serving(user.id, queue.id, ticket.id)
    assert serving.status == :serving
    assert serving.started_at

    event = ticket_event(ticket.id)
    assert event.from_status == :called
    assert event.to_status == :serving
    assert event.actor_type == :staff
    assert event.actor_id == user.id
    assert DateTime.compare(event.occurred_at, serving.started_at) == :eq
  end

  test "rejects a repeated start without adding a duplicate event" do
    %{user: user, queue: queue, session: session} = staff_queue_fixture()
    ticket = create_ticket(session, :called)

    assert {:ok, _serving} = StaffStartServing.start_serving(user.id, queue.id, ticket.id)
    assert {:error, :not_called} = StaffStartServing.start_serving(user.id, queue.id, ticket.id)
    assert event_count(ticket.id) == 1
  end

  test "rejects tickets that are not called and users without queue access" do
    %{user: user, queue: queue, session: session} = staff_queue_fixture()
    waiting_ticket = create_ticket(session, :waiting)
    %{user: unassigned_user} = staff_queue_fixture(assign_access?: false)

    assert {:error, :not_called} =
             StaffStartServing.start_serving(user.id, queue.id, waiting_ticket.id)

    assert {:error, :not_found} =
             StaffStartServing.start_serving(unassigned_user.id, queue.id, waiting_ticket.id)

    assert event_count(waiting_ticket.id) == 0
  end

  defp ticket_event(ticket_id) do
    TicketEvent
    |> Ash.Query.filter(ticket_id == ^ticket_id)
    |> Ash.read_one!(domain: Kewkew.Queues)
  end

  defp event_count(ticket_id) do
    TicketEvent
    |> Ash.Query.filter(ticket_id == ^ticket_id)
    |> Ash.count!(domain: Kewkew.Queues)
  end

  defp staff_queue_fixture(opts \\ []) do
    organization =
      Ash.create!(Kewkew.Business.Organization, %{name: "Queue organization"},
        domain: Kewkew.Business,
        authorize?: false
      )

    location =
      Ash.create!(
        Kewkew.Business.Location,
        %{name: "Main location", organization_id: organization.id},
        domain: Kewkew.Business,
        authorize?: false
      )

    service =
      Ash.create!(Kewkew.Business.Service, %{name: "Customer service", location_id: location.id},
        domain: Kewkew.Business,
        authorize?: false
      )

    queue =
      Ash.create!(
        Kewkew.Queues.Queue,
        %{
          name: "Main queue",
          public_slug: "main-#{System.unique_integer([:positive])}",
          location_id: location.id,
          service_id: service.id
        },
        domain: Kewkew.Queues,
        authorize?: false
      )

    session =
      Ash.create!(Kewkew.Queues.QueueSession, %{queue_id: queue.id},
        domain: Kewkew.Queues,
        authorize?: false
      )

    user =
      Ash.create!(
        Kewkew.Accounts.User,
        %{
          email: "staff-#{System.unique_integer([:positive])}@example.com",
          password: "valid-staff-password"
        },
        action: :provision_staff_user,
        domain: Kewkew.Accounts,
        authorize?: false
      )

    if Keyword.get(opts, :assign_access?, true) do
      Ash.create!(
        Kewkew.Business.StaffMembership,
        %{user_id: user.id, organization_id: organization.id, role: :admin},
        action: :grant,
        domain: Kewkew.Business,
        authorize?: false
      )
    end

    %{user: user, queue: queue, session: session}
  end

  defp create_ticket(session, status) do
    ticket =
      Ash.create!(
        Ticket,
        %{
          queue_session_id: session.id,
          ticket_number: 1,
          queue_sequence: 1
        },
        action: :join_visitor,
        domain: Kewkew.Queues,
        authorize?: false
      )

    if status == :called do
      ticket
      |> Ecto.Changeset.change(status: :called, called_at: DateTime.utc_now())
      |> Repo.update!()
    else
      ticket
    end
  end
end
