defmodule Kewkew.Queues.Ticket do
  @moduledoc "A visitor's place in one queue session."

  use Ash.Resource,
    otp_app: :kewkew,
    domain: Kewkew.Queues,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "tickets"
    repo Kewkew.Repo

    custom_indexes do
      index [:queue_session_id, :ticket_number], unique: true
      index [:queue_session_id, :queue_sequence], unique: true
      index [:queue_session_id, :status, :queue_sequence]
    end
  end

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id

    attribute :ticket_number, :integer do
      allow_nil? false
      constraints min: 1
      public? true
    end

    attribute :queue_sequence, :integer do
      allow_nil? false
      constraints min: 1
      public? false
    end

    attribute :status, :atom do
      allow_nil? false
      default :waiting
      constraints one_of: [:waiting, :called, :serving, :completed, :cancelled, :no_show]
      public? true
    end

    attribute :first_name, :string do
      sensitive? true
      public? true
    end

    attribute :last_name, :string do
      sensitive? true
      public? true
    end

    attribute :joined_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      public? true
    end

    attribute :called_at, :utc_datetime_usec do
      public? true
    end

    attribute :started_at, :utc_datetime_usec do
      public? true
    end

    attribute :completed_at, :utc_datetime_usec do
      public? true
    end

    attribute :cancelled_at, :utc_datetime_usec do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :queue_session, Kewkew.Queues.QueueSession do
      allow_nil? false
      public? true
    end

    has_many :events, Kewkew.Queues.TicketEvent
    has_many :tracking_credentials, Kewkew.Queues.TrackingCredential
  end
end
