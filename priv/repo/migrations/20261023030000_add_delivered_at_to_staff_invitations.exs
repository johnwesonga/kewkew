defmodule Kewkew.Repo.Migrations.AddDeliveredAtToStaffInvitations do
  use Ecto.Migration

  def change do
    alter table(:staff_invitations) do
      add :delivered_at, :utc_datetime_usec
    end
  end
end
