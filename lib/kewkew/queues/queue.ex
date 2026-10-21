defmodule Kewkew.Queues.Queue do
  @moduledoc "Reusable configuration for a service queue at a location."

  use Ash.Resource,
    otp_app: :kewkew,
    domain: Kewkew.Queues,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "queues"
    repo Kewkew.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :name,
        :public_slug,
        :identity_policy,
        :max_active_tickets,
        :location_id,
        :service_id
      ]
    end

    read :by_public_slug do
      argument :slug, :string do
        allow_nil? false
      end

      filter expr(public_slug == ^arg(:slug))
      prepare build(load: [:location, :service])
      get? true
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :public_slug, :string do
      allow_nil? false
      public? true
    end

    attribute :identity_policy, :atom do
      allow_nil? false
      default :anonymous
      constraints one_of: [:anonymous, :name_required]
      public? true
    end

    attribute :max_active_tickets, :integer do
      constraints min: 1
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :location, Kewkew.Business.Location do
      allow_nil? false
      public? true
    end

    belongs_to :service, Kewkew.Business.Service do
      allow_nil? false
      public? true
    end

    has_many :sessions, Kewkew.Queues.QueueSession
  end

  identities do
    identity :unique_public_slug, [:public_slug]
  end
end
