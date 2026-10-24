defmodule Kewkew.Business.StaffLocationAccess do
  @moduledoc "A location assignment for an organization staff operator."

  use Ash.Resource,
    otp_app: :kewkew,
    domain: Kewkew.Business,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "staff_location_accesses"
    repo Kewkew.Repo

    custom_indexes do
      index [:staff_membership_id, :location_id], unique: true
    end
  end

  actions do
    defaults [:read]

    create :assign do
      accept [:staff_membership_id, :location_id]
    end

    destroy :unassign
  end

  policies do
    policy action([:assign, :unassign]) do
      authorize_if {Kewkew.Business.Policies.ActiveOrganizationAdmin, []}
    end

    policy action(:read) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :staff_membership, Kewkew.Business.StaffMembership do
      allow_nil? false
      public? true
    end

    belongs_to :location, Kewkew.Business.Location do
      allow_nil? false
      public? true
    end
  end
end
