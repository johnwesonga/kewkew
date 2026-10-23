defmodule Kewkew.Repo.Migrations.CreateStaffInvitations do
  use Ecto.Migration

  def change do
    create table(:staff_invitations, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :email, :citext, null: false
      add :role, :text, null: false
      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :delivered_at, :utc_datetime_usec
      add :accepted_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      add :location_ids, {:array, :binary_id}, null: false, default: []

      add :organization_id, references(:organizations, type: :uuid, on_delete: :delete_all),
        null: false

      add :invited_by_id, references(:users, type: :uuid, on_delete: :nilify_all), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:staff_invitations, [:token_hash])
    create index(:staff_invitations, [:organization_id, :email])
  end
end
