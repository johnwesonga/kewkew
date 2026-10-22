defmodule Kewkew.Queues.StaffRecallNoShowTest do
  use Kewkew.DataCase

  require Ash.Query

  alias Kewkew.Queues.{
    PublicLookup,
    StaffBoard,
    StaffRecallNoShow,
    TicketEvent,
    VisitorJoin,
    Updates
  }

  test "requeues a no-show at the end, preserves its number, and updates visitor position" do
    %{user: user, queue: queue, session: session} = staff_queue_fixture()
    returning_token = tracking_token()
    waiting_token = tracking_token()

    assert {:ok, returning} = VisitorJoin.join_anonymous(queue.public_slug, returning_token)
    assert {:ok, waiting} = VisitorJoin.join_anonymous(queue.public_slug, waiting_token)

    returning_ticket = set_status(returning.ticket, :no_show)
    :ok = Updates.subscribe(session.id)

    assert {:ok, recalled} =
             StaffRecallNoShow.recall_no_show(user.id, queue.id, returning_ticket.id)

    assert_receive {:queue_session_updated, session_id}
    assert session_id == session.id
    assert recalled.status == :waiting
    assert recalled.ticket_number == returning_ticket.ticket_number
    assert recalled.queue_sequence > waiting.ticket.queue_sequence

    assert {:ok, board} = StaffBoard.fetch_queue(user.id, queue.id)
    assert Enum.map(board.tickets, & &1.id) == [waiting.ticket.id, returning.ticket.id]

    assert {:ok, visitor_state} = PublicLookup.fetch_tracking_ticket(returning_token)
    assert visitor_state.ticket.status == :waiting
    assert visitor_state.position == 2

    event = ticket_event(returning_ticket.id)
    assert event.from_status == :no_show
    assert event.to_status == :waiting
    assert event.actor_type == :staff
    assert event.actor_id == user.id
  end

  test "rejects repeated recall and tickets outside the current no-show state" do
    %{user: user, queue: queue, session: session} = staff_queue_fixture()
    token = tracking_token()
    assert {:ok, joined} = VisitorJoin.join_anonymous(queue.public_slug, token)
    ticket = set_status(joined.ticket, :no_show)
    :ok = Updates.subscribe(session.id)

    assert {:ok, _recalled} = StaffRecallNoShow.recall_no_show(user.id, queue.id, ticket.id)
    assert_receive {:queue_session_updated, session_id}

    assert {:error, :not_no_show} =
             StaffRecallNoShow.recall_no_show(user.id, queue.id, ticket.id)

    refute_receive {:queue_session_updated, ^session_id}
    assert event_count(ticket.id) == 2
  end

  test "rejects a ticket from a user without access" do
    %{user: user, queue: queue} = staff_queue_fixture()
    %{user: unassigned_user} = staff_queue_fixture(assign_access?: false)
    token = tracking_token()
    assert {:ok, joined} = VisitorJoin.join_anonymous(queue.public_slug, token)
    ticket = set_status(joined.ticket, :no_show)

    assert {:error, :not_found} =
             StaffRecallNoShow.recall_no_show(unassigned_user.id, queue.id, ticket.id)

    assert event_count(ticket.id) == 1
    assert user.id != unassigned_user.id
  end

  defp set_status(ticket, status) do
    ticket
    |> Ecto.Changeset.change(status: status)
    |> Repo.update!()
  end

  defp tracking_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp ticket_event(ticket_id) do
    [event | _] =
      TicketEvent
      |> Ash.Query.filter(ticket_id == ^ticket_id)
      |> Ash.Query.sort(occurred_at: :desc)
      |> Ash.read!(domain: Kewkew.Queues)

    event
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
end
