defmodule Kewkew.Business.StaffMembership do
  @moduledoc "A user's active role within a business organization."

  use Ash.Resource,
    otp_app: :kewkew,
    domain: Kewkew.Business,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "staff_memberships"
    repo Kewkew.Repo

    custom_indexes do
      index [:user_id, :organization_id], unique: true
    end
  end

  actions do
    defaults [:read]

    create :grant do
      accept [:user_id, :organization_id, :role]
    end

    update :change_role do
      accept [:role, :active?]
    end
  end

  policies do
    policy action(:change_role) do
      authorize_if {Kewkew.Business.Policies.ActiveOrganizationAdmin, []}
    end

    policy action([:read, :grant]) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :role, :atom do
      allow_nil? false
      constraints one_of: [:admin, :operator]
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
    belongs_to :user, Kewkew.Accounts.User do
      allow_nil? false
      public? true
    end

    belongs_to :organization, Kewkew.Business.Organization do
      allow_nil? false
      public? true
    end

    has_many :location_accesses, Kewkew.Business.StaffLocationAccess do
      public? true
    end
  end
end
