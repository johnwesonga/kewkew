defmodule Kewkew.Repo.Migrations.CreateBrowserTicketClaims do
  use Ecto.Migration

  def change do
    create table(:browser_ticket_claims, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :queue_session_id,
          references(:queue_sessions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :ticket_id,
          references(:tickets, type: :binary_id, on_delete: :delete_all),
          null: false

      add :credential_digest, :string, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:browser_ticket_claims, [:queue_session_id, :credential_digest])
    create unique_index(:browser_ticket_claims, [:ticket_id])
  end
end
