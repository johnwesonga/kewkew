defmodule Kewkew.Queues.StaffCancelTicketTest do
  use Kewkew.DataCase

  require Ash.Query

  alias Kewkew.Queues.{StaffBoard, StaffCancelTicket, Ticket, TicketEvent}

  test "cancels waiting and called tickets with staff-attributed history" do
    %{user: user, queue: queue, session: session} = staff_queue_fixture()

    for {status, sequence} <- [waiting: 1, called: 2] do
      ticket = create_ticket(session, status, sequence)

      assert {:ok, cancelled} = StaffCancelTicket.cancel_ticket(user.id, queue.id, ticket.id)
      assert cancelled.status == :cancelled
      assert cancelled.cancelled_at

      event = ticket_event(ticket.id)
      assert event.from_status == status
      assert event.to_status == :cancelled
      assert event.actor_type == :staff
      assert event.actor_id == user.id
      assert DateTime.compare(event.occurred_at, cancelled.cancelled_at) == :eq
    end

    assert {:ok, board} = StaffBoard.fetch_queue(user.id, queue.id)
    assert board.tickets == []
  end

  test "rejects a repeated cancellation without writing another event" do
    %{user: user, queue: queue, session: session} = staff_queue_fixture()
    ticket = create_ticket(session, :called, 1)

    assert {:ok, _cancelled} = StaffCancelTicket.cancel_ticket(user.id, queue.id, ticket.id)

    assert {:error, :not_cancellable} =
             StaffCancelTicket.cancel_ticket(user.id, queue.id, ticket.id)

    assert event_count(ticket.id) == 1
  end

  test "cannot cancel a serving ticket or act without queue access" do
    %{user: user, queue: queue, session: session} = staff_queue_fixture()
    serving_ticket = create_ticket(session, :serving, 1)
    %{user: unassigned_user} = staff_queue_fixture(assign_access?: false)

    assert {:error, :not_cancellable} =
             StaffCancelTicket.cancel_ticket(user.id, queue.id, serving_ticket.id)

    assert {:error, :not_found} =
             StaffCancelTicket.cancel_ticket(unassigned_user.id, queue.id, serving_ticket.id)

    assert event_count(serving_ticket.id) == 0
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

  defp create_ticket(session, status, sequence) do
    ticket =
      Ash.create!(
        Ticket,
        %{
          queue_session_id: session.id,
          ticket_number: sequence,
          queue_sequence: sequence
        },
        action: :join_visitor,
        domain: Kewkew.Queues,
        authorize?: false
      )

    now = DateTime.utc_now()

    ticket_changes =
      case status do
        :waiting -> []
        :called -> [status: :called, called_at: now]
        :serving -> [status: :serving, called_at: now, started_at: now]
      end

    ticket
    |> Ecto.Changeset.change(ticket_changes)
    |> Repo.update!()
  end
end
