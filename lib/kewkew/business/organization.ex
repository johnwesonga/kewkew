defmodule Kewkew.Business.Organization do
  @moduledoc "A business tenant that owns operating locations."

  use Ash.Resource,
    otp_app: :kewkew,
    domain: Kewkew.Business,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "organizations"
    repo Kewkew.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:name]
    end
  end

  policies do
    policy always() do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
end
