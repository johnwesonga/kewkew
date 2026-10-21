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
      accept [:name, :description, :active?, :location_id]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
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
