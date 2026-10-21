defmodule Kewkew.Queues.TrackingCredential do
  @moduledoc "Digest-backed bearer credential for a visitor's private ticket page."

  use Ash.Resource,
    otp_app: :kewkew,
    domain: Kewkew.Queues,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "tracking_credentials"
    repo Kewkew.Repo

    custom_indexes do
      index [:token_digest], unique: true
      index [:ticket_id]
    end
  end

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id

    attribute :token_digest, :string do
      allow_nil? false
      sensitive? true
      public? false
    end

    attribute :expires_at, :utc_datetime_usec do
      public? false
    end

    attribute :revoked_at, :utc_datetime_usec do
      public? false
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :ticket, Kewkew.Queues.Ticket do
      allow_nil? false
      public? false
    end
  end
end
