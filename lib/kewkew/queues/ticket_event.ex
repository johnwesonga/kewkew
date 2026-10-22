defmodule Kewkew.Queues.TicketEvent do
  @moduledoc "Append-only record of a ticket status transition."

  use Ash.Resource,
    otp_app: :kewkew,
    domain: Kewkew.Queues,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "ticket_events"
    repo Kewkew.Repo

    custom_indexes do
      index [:ticket_id, :occurred_at]
    end
  end

  actions do
    defaults [:read]

    create :record_transition do
      accept [:ticket_id, :from_status, :to_status, :actor_type, :actor_id, :occurred_at]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :from_status, :atom do
      constraints one_of: [:waiting, :called, :serving, :completed, :cancelled, :no_show]
      public? true
    end

    attribute :to_status, :atom do
      allow_nil? false
      constraints one_of: [:waiting, :called, :serving, :completed, :cancelled, :no_show]
      public? true
    end

    attribute :actor_type, :atom do
      allow_nil? false
      constraints one_of: [:visitor, :staff, :system]
      public? true
    end

    attribute :actor_id, :uuid do
      public? true
    end

    attribute :occurred_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      public? true
    end

    attribute :metadata, :map do
      public? false
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :ticket, Kewkew.Queues.Ticket do
      allow_nil? false
      public? true
    end
  end
end
