defmodule Kewkew.Business.Policies.ActiveOrganizationAdmin do
  @moduledoc "Authorizes access changes by active administrators of the target organization."

  use Ash.Policy.SimpleCheck

  import Ecto.Query

  alias Kewkew.Business.StaffMembership
  alias Kewkew.Repo

  @impl true
  def describe(_opts), do: "actor is an active administrator of the target organization"

  @impl true
  def match?(%{id: actor_id}, %{subject: %{data: %{organization_id: organization_id}}}, _opts)
      when is_binary(actor_id) and is_binary(organization_id) do
    Repo.exists?(
      from membership in StaffMembership,
        where:
          membership.user_id == ^actor_id and
            membership.organization_id == ^organization_id and
            membership.active? and membership.role == :admin
    )
  end

  def match?(_actor, _context, _opts), do: false
end
