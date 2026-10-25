defmodule Kewkew.Business.Service do
  @moduledoc "A service that visitors can join at a location."

  use Ash.Resource,
    otp_app: :kewkew,
    domain: Kewkew.Business,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "services"
    repo Kewkew.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:name, :description, :visitor_instructions, :location_id]
    end

    update :update_details do
      accept [:name, :description, :visitor_instructions]
    end

    update :set_active do
      accept [:active?]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 120
    end

    attribute :description, :string do
      public? true
      constraints max_length: 1000
    end

    attribute :visitor_instructions, :string do
      public? true
      constraints max_length: 500
    end

    attribute :active?, :boolean do
      allow_nil? false
      default true
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
  end
end
