defmodule Kewkew.Queues.StaffQueueStatsTest do
  use Kewkew.DataCase

  alias Kewkew.Queues.{QueueSession, StaffQueueStats, Ticket}

  test "aggregates served tickets and average wait by UTC completion date" do
    %{user: user, queue: queue, session: session} = staff_queue_fixture()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    create_ticket(session, :completed, now,
      joined_at: DateTime.add(now, -30 * 60, :second),
      started_at: DateTime.add(now, -15 * 60, :second)
    )

    create_ticket(session, :completed, now,
      joined_at: DateTime.add(now, -60 * 60, :second),
      started_at: DateTime.add(now, -15 * 60, :second)
    )

    create_ticket(session, :completed, now, joined_at: DateTime.add(now, -60 * 60, :second))
    create_ticket(session, :cancelled, now)
    create_ticket(session, :no_show, now)

    create_ticket(session, :completed, DateTime.add(now, -8 * 86_400, :second),
      joined_at: DateTime.add(now, -9 * 86_400, :second),
      started_at: DateTime.add(now, -8 * 86_400, :second)
    )

    create_ticket(session, :completed, DateTime.add(now, -45 * 86_400, :second),
      joined_at: DateTime.add(now, -46 * 86_400, :second),
      started_at: DateTime.add(now, -45 * 86_400, :second)
    )

    assert {:ok, stats} = StaffQueueStats.fetch(user.id, queue.id, 7)
    assert length(stats.points) == 7
    assert stats.days == 7
    assert stats.last_day == DateTime.to_date(now)

    today = List.last(stats.points)
    assert today.date == DateTime.to_date(now)
    assert today.served == 3
    assert today.wait_count == 2
    assert_in_delta today.average_wait_minutes, 30, 0.01

    assert Enum.reduce(stats.points, 0, &(&1.served + &2)) == 3

    assert {:ok, thirty_days} = StaffQueueStats.fetch(user.id, queue.id, 30)
    assert Enum.reduce(thirty_days.points, 0, &(&1.served + &2)) == 4

    assert {:ok, ninety_days} = StaffQueueStats.fetch(user.id, queue.id, 90)
    assert Enum.reduce(ninety_days.points, 0, &(&1.served + &2)) == 5
  end

  test "returns zeroed daily points for a queue without completed tickets" do
    %{user: user, queue: queue} = staff_queue_fixture()

    assert {:ok, stats} = StaffQueueStats.fetch(user.id, queue.id, 7)
    assert length(stats.points) == 7
    assert Enum.all?(stats.points, &(&1.served == 0 and is_nil(&1.average_wait_minutes)))
  end

  test "does not return statistics for a queue the staff member cannot access" do
    %{queue: queue} = staff_queue_fixture()
    %{user: other_user} = staff_queue_fixture()

    assert {:error, :not_found} = StaffQueueStats.fetch(other_user.id, queue.id, 30)
  end

  test "accepts only the supported date ranges" do
    %{user: user, queue: queue} = staff_queue_fixture()

    assert {:error, :invalid_period} = StaffQueueStats.fetch(user.id, queue.id, 14)
  end

  defp create_ticket(session, status, completed_at, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    joined_at = Keyword.get(opts, :joined_at, now)
    started_at = Keyword.get(opts, :started_at)

    ticket =
      Ash.create!(
        Ticket,
        %{
          queue_session_id: session.id,
          ticket_number: System.unique_integer([:positive]),
          queue_sequence: System.unique_integer([:positive])
        },
        action: :join_visitor,
        domain: Kewkew.Queues,
        authorize?: false
      )

    ticket
    |> Ecto.Changeset.change(
      status: status,
      joined_at: joined_at,
      started_at: started_at,
      completed_at: if(status == :completed, do: completed_at),
      cancelled_at: if(status == :cancelled, do: completed_at)
    )
    |> Repo.update!()
  end

  defp staff_queue_fixture do
    organization =
      Ash.create!(Kewkew.Business.Organization, %{name: "Stats organization"},
        domain: Kewkew.Business,
        authorize?: false
      )

    location =
      Ash.create!(
        Kewkew.Business.Location,
        %{name: "Stats location", organization_id: organization.id},
        domain: Kewkew.Business,
        authorize?: false
      )

    service =
      Ash.create!(Kewkew.Business.Service, %{name: "Stats service", location_id: location.id},
        domain: Kewkew.Business,
        authorize?: false
      )

    queue =
      Ash.create!(
        Kewkew.Queues.Queue,
        %{
          name: "Stats queue",
          public_slug: "stats-#{System.unique_integer([:positive])}",
          location_id: location.id,
          service_id: service.id
        },
        domain: Kewkew.Queues,
        authorize?: false
      )

    session =
      Ash.create!(QueueSession, %{queue_id: queue.id},
        domain: Kewkew.Queues,
        authorize?: false
      )

    user =
      Ash.create!(
        Kewkew.Accounts.User,
        %{
          email: "stats-#{System.unique_integer([:positive])}@example.com",
          password: "valid-staff-password"
        },
        action: :provision_staff_user,
        domain: Kewkew.Accounts,
        authorize?: false
      )

    Ash.create!(
      Kewkew.Business.StaffMembership,
      %{user_id: user.id, organization_id: organization.id, role: :admin},
      action: :grant,
      domain: Kewkew.Business,
      authorize?: false
    )

    %{user: user, queue: queue, session: session}
  end
end
