defmodule Kewkew.Business.Location do
  @moduledoc "A physical place where a business provides services."

  use Ash.Resource,
    otp_app: :kewkew,
    domain: Kewkew.Business,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "locations"
    repo Kewkew.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:name, :timezone, :active?]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :timezone, :string do
      allow_nil? false
      default "Etc/UTC"
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
end
