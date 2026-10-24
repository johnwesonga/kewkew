defmodule Kewkew.Business.StaffInvitation do
  @moduledoc "A one-time, email-bound invitation to join an organization."

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "staff_invitations" do
    field :email, :string
    field :role, Ecto.Enum, values: [:admin, :operator]
    field :token_hash, :binary
    field :expires_at, :utc_datetime_usec
    field :accepted_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    field :delivered_at, :utc_datetime_usec
    field :location_ids, {:array, :binary_id}, default: []
    field :organization_name, :string, virtual: true

    belongs_to :organization, Kewkew.Business.Organization
    belongs_to :invited_by, Kewkew.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [
      :email,
      :role,
      :token_hash,
      :expires_at,
      :organization_id,
      :invited_by_id
    ])
    |> validate_required([
      :email,
      :role,
      :token_hash,
      :expires_at,
      :organization_id,
      :invited_by_id
    ])
    |> update_change(:email, &String.downcase(String.trim(&1)))
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/)
  end
end
