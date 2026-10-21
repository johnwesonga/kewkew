defmodule Kewkew.Queues.QueueSession do
  @moduledoc "One operating period for a reusable queue. Ticket numbering restarts each session."

  use Ash.Resource,
    otp_app: :kewkew,
    domain: Kewkew.Queues,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "queue_sessions"
    repo Kewkew.Repo

    custom_indexes do
      index [:queue_id], unique: true, where: "status IN ('open', 'paused')"
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:status, :opened_at, :queue_id]
    end

    read :latest_for_queue do
      argument :queue_id, :uuid do
        allow_nil? false
      end

      filter expr(queue_id == ^arg(:queue_id))
      prepare build(sort: [opened_at: :desc], limit: 1)
      get? true
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      allow_nil? false
      default :open
      constraints one_of: [:open, :paused, :closed]
      public? true
    end

    attribute :next_ticket_number, :integer do
      allow_nil? false
      default 1
      constraints min: 1
      public? false
    end

    attribute :next_queue_sequence, :integer do
      allow_nil? false
      default 1
      constraints min: 1
      public? false
    end

    attribute :opened_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      public? true
    end

    attribute :closed_at, :utc_datetime_usec do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :queue, Kewkew.Queues.Queue do
      allow_nil? false
      public? true
    end

    has_many :tickets, Kewkew.Queues.Ticket
  end
end
