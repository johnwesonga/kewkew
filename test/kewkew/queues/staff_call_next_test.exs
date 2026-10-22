defmodule Kewkew.Queues.StaffCallNextTest do
  use Kewkew.DataCase

  require Ash.Query

  alias Kewkew.Queues.{StaffCallNext, Ticket, TicketEvent, Updates}

  test "calls the earliest waiting ticket and records its staff actor atomically" do
    %{user: user, queue: queue, session: session} = staff_queue_fixture()
    later = create_ticket(session, 8, 2)
    first = create_ticket(session, 19, 1)
    :ok = Updates.subscribe(session.id)

    assert {:ok, called} = StaffCallNext.call_next(user.id, queue.id)
    assert_receive {:queue_session_updated, session_id}
    assert session_id == session.id
    assert called.id == first.id
    assert called.status == :called
    assert called.called_at

    event =
      TicketEvent
      |> Ash.Query.filter(ticket_id == ^first.id)
      |> Ash.read_one!(domain: Kewkew.Queues)

    assert event.from_status == :waiting
    assert event.to_status == :called
    assert event.actor_type == :staff
    assert event.actor_id == user.id
    assert DateTime.compare(event.occurred_at, called.called_at) == :eq

    assert {:ok, next} = StaffCallNext.call_next(user.id, queue.id)
    assert_receive {:queue_session_updated, ^session_id}
    assert next.id == later.id
  end

  test "returns no_waiting when no ticket remains and does not write an event" do
    %{user: user, queue: queue, session: session} = staff_queue_fixture()
    :ok = Updates.subscribe(session.id)

    assert {:error, :no_waiting} = StaffCallNext.call_next(user.id, queue.id)
    refute_receive {:queue_session_updated, _session_id}

    assert Ash.count!(TicketEvent, domain: Kewkew.Queues) == 0
  end

  test "does not allow a staff user without location access to call tickets" do
    %{queue: queue} = staff_queue_fixture()
    %{user: unassigned_user} = staff_queue_fixture(assign_access?: false)

    assert {:error, :not_found} = StaffCallNext.call_next(unassigned_user.id, queue.id)
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

  defp create_ticket(session, ticket_number, sequence) do
    Ash.create!(
      Ticket,
      %{
        queue_session_id: session.id,
        ticket_number: ticket_number,
        queue_sequence: sequence
      },
      action: :join_visitor,
      domain: Kewkew.Queues,
      authorize?: false
    )
  end
end
