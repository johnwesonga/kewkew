defmodule Kewkew.Business.StaffUpdateOrganization do
  @moduledoc "Updates organization profile details for authorized administrators."

  import Ecto.Query

  alias Kewkew.Business.{Organization, StaffMembership}
  alias Kewkew.Repo

  @doc "Fetches an organization only when the user has an active admin membership."
  def fetch_organization(user_id, organization_id) do
    with {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, organization_id} <- Ecto.UUID.cast(organization_id),
         %Organization{} = organization <- organization_query(user_id, organization_id) do
      {:ok, organization}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Updates the organization name after rechecking admin access in the write transaction."
  def update_name(user_id, organization_id, name)
      when is_binary(user_id) and is_binary(organization_id) and is_binary(name) do
    with {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, organization_id} <- Ecto.UUID.cast(organization_id) do
      name = String.trim(name)

      case Repo.transaction(fn ->
             organization =
               organization_query(user_id, organization_id, lock?: true) ||
                 Repo.rollback(:not_found)

             case Ash.update(organization, %{name: name},
                    action: :update_profile,
                    domain: Kewkew.Business,
                    authorize?: false
                  ) do
               {:ok, organization} -> organization
               {:error, _error} -> Repo.rollback(:invalid_name)
             end
           end) do
        {:ok, organization} -> {:ok, organization}
        {:error, reason} -> {:error, reason}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  def update_name(_user_id, _organization_id, _name), do: {:error, :invalid_name}

  defp organization_query(user_id, organization_id, opts \\ []) do
    query =
      from organization in Organization,
        join: membership in StaffMembership,
        on: membership.organization_id == organization.id,
        where:
          organization.id == ^organization_id and membership.user_id == ^user_id and
            membership.active? and membership.role == :admin,
        limit: 1

    query = if Keyword.get(opts, :lock?, false), do: lock(query, "FOR UPDATE"), else: query

    Repo.one(query)
  end
end
