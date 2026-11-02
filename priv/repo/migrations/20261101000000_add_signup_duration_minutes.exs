defmodule Kewkew.Repo.Migrations.AddSignupDurationMinutes do
  use Ecto.Migration

  def change do
    alter table(:queue_schedules) do
      add :signup_duration_minutes, :bigint
    end

    create constraint(:queue_schedules, :signup_duration_minutes_range,
             check:
               "signup_duration_minutes IS NULL OR signup_duration_minutes BETWEEN 1 AND 1440"
           )
  end
end
