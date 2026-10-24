defmodule Kewkew.Business.Policies.ActiveOrganizationAdmin do
  @moduledoc "Authorizes access changes by active administrators of the target organization."

  use Ash.Policy.SimpleCheck

  import Ecto.Query

  alias Kewkew.Business.StaffMembership
  alias Kewkew.Repo

  @impl true
  def describe(_opts), do: "actor is an active administrator of the target organization"

  @impl true
  def match?(%{id: actor_id}, %{subject: subject}, _opts) when is_binary(actor_id) do
    data = Map.get(subject, :data, %{})
    attributes = Map.get(subject, :attributes, %{})

    cond do
      is_binary(Map.get(data, :organization_id)) ->
        active_organization_admin?(actor_id, organization_id: data.organization_id)

      is_binary(Map.get(attributes, :staff_membership_id)) ->
        active_organization_admin?(actor_id,
          membership_id: attributes.staff_membership_id,
          location_id: Map.get(attributes, :location_id)
        )

      is_binary(Map.get(data, :staff_membership_id)) ->
        active_organization_admin?(actor_id,
          membership_id: data.staff_membership_id,
          location_id: Map.get(data, :location_id)
        )

      true ->
        false
    end
  end

  def match?(_actor, _context, _opts), do: false

  defp active_organization_admin?(actor_id, organization_id: organization_id) do
    Repo.exists?(
      from membership in StaffMembership,
        where:
          membership.user_id == ^actor_id and
            membership.organization_id == ^organization_id and
            membership.active? and membership.role == :admin
    )
  end

  defp active_organization_admin?(actor_id,
         membership_id: membership_id,
         location_id: location_id
       )
       when is_binary(location_id) do
    Repo.exists?(
      from target in StaffMembership,
        join: administrator in StaffMembership,
        on: administrator.organization_id == target.organization_id,
        join: location in Kewkew.Business.Location,
        on: location.organization_id == target.organization_id,
        where:
          target.id == ^membership_id and administrator.user_id == ^actor_id and
            administrator.active? and administrator.role == :admin and location.id == ^location_id
    )
  end

  defp active_organization_admin?(_actor_id,
         membership_id: _membership_id,
         location_id: _location_id
       ),
       do: false
end
