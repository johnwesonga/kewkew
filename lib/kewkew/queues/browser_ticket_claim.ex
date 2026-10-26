defmodule Kewkew.Queues.BrowserTicketClaim do
  @moduledoc "Associates one browser credential with its active ticket in a queue session."

  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  schema "browser_ticket_claims" do
    field :credential_digest, :string

    belongs_to :queue_session, Kewkew.Queues.QueueSession
    belongs_to :ticket, Kewkew.Queues.Ticket

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
