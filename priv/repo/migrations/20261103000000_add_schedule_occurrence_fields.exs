defmodule Kewkew.Repo.Migrations.AddScheduleOccurrenceFields do
  use Ecto.Migration

  def change do
    alter table(:queue_sessions) do
      add :scheduled_service_start_at, :utc_datetime_usec
      add :ticket_cap, :bigint
    end

    create constraint(:queue_sessions, :queue_sessions_ticket_cap_positive,
             check: "ticket_cap IS NULL OR ticket_cap > 0"
           )

    execute """
    UPDATE queue_sessions AS sessions
    SET scheduled_service_start_at =
          ((timezone(locations.timezone, sessions.opened_at)::date + schedules.service_start_time)
            AT TIME ZONE locations.timezone),
        ticket_cap = schedules.ticket_cap
    FROM queues, locations, queue_schedules AS schedules
    WHERE sessions.queue_id = queues.id
      AND queues.location_id = locations.id
      AND schedules.queue_id = queues.id
      AND EXTRACT(ISODOW FROM timezone(locations.timezone, sessions.opened_at)::date)::integer
            = ANY(schedules.weekdays)
    """
  end
end
