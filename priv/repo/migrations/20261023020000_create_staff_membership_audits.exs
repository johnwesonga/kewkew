defmodule Kewkew.Repo.Migrations.CreateStaffMembershipAudits do
  use Ecto.Migration

  def change do
    create table(:staff_membership_audits, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :change, :text, null: false
      add :occurred_at, :utc_datetime_usec, null: false
      add :actor_id, references(:users, type: :uuid, on_delete: :nilify_all), null: false
      add :member_id, references(:users, type: :uuid, on_delete: :nilify_all), null: false

      add :organization_id, references(:organizations, type: :uuid, on_delete: :delete_all),
        null: false

      add :membership_id,
          references(:staff_memberships, type: :uuid, on_delete: :nilify_all),
          null: false
    end

    create index(:staff_membership_audits, [:organization_id, :occurred_at])
    create index(:staff_membership_audits, [:membership_id, :occurred_at])
  end
end
