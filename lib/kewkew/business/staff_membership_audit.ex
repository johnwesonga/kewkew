defmodule Kewkew.Business.StaffMembershipAudit do
  @moduledoc "Append-only record of organization membership access changes."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "staff_membership_audits" do
    field :change, Ecto.Enum, values: [:suspended, :restored]
    belongs_to :actor, Kewkew.Accounts.User
    belongs_to :member, Kewkew.Accounts.User
    belongs_to :organization, Kewkew.Business.Organization
    belongs_to :membership, Kewkew.Business.StaffMembership
    field :occurred_at, :utc_datetime_usec
  end
end
