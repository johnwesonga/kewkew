defmodule Kewkew.Business.StaffLocationAdministration do
  @moduledoc "Creates and updates locations for organization administrators."

  import Ecto.Query

  alias Kewkew.Business.{Location, Organization, StaffMembership}
  alias Kewkew.Repo

  @supported_timezones [
    "America/Los_Angeles",
    "US/Mountain",
    "America/New_York",
    "Africa/Nairobi"
  ]

  @doc "Fetches an organization only when the user has an active admin membership."
  def fetch_organization(user_id, organization_id) do
    with {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, organization_id} <- Ecto.UUID.cast(organization_id),
         %Organization{} = organization <- admin_organization(user_id, organization_id) do
      {:ok, organization}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Fetches a location only when the user is an administrator of its organization."
  def fetch_location(user_id, location_id) do
    with {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, location_id} <- Ecto.UUID.cast(location_id),
         %{location: %Location{}} = context <- admin_location(user_id, location_id) do
      {:ok, context}
    else
      _ -> {:error, :not_found}
    end
  end

  def locations_for_organization(organization_id) do
    Repo.all(
      from location in Location,
        where: location.organization_id == ^organization_id,
        order_by: location.name
    )
  end

  @doc "Creates a location within an organization the user actively administers."
  def create_location(user_id, organization_id, params) when is_map(params) do
    with {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, organization_id} <- Ecto.UUID.cast(organization_id),
         {:ok, details} <- validate_details(params) do
      case Repo.transaction(fn ->
             organization =
               admin_organization(user_id, organization_id, lock?: true) ||
                 Repo.rollback(:not_found)

             case Ash.create(
                    Location,
                    Map.put(details, :organization_id, organization.id),
                    domain: Kewkew.Business,
                    authorize?: false
                  ) do
               {:ok, location} -> location
               {:error, _error} -> Repo.rollback(:invalid_location)
             end
           end) do
        {:ok, location} -> {:ok, location}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, {:invalid_params, errors}} -> {:error, :invalid_params, errors}
      _ -> {:error, :not_found}
    end
  end

  def create_location(_user_id, _organization_id, _params), do: {:error, :not_found}

  @doc "Updates a location's name and timezone without accepting organization changes."
  def update_location(user_id, location_id, params) when is_map(params) do
    with {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, location_id} <- Ecto.UUID.cast(location_id),
         {:ok, details} <- validate_details(params) do
      case Repo.transaction(fn ->
             %{location: location} =
               admin_location(user_id, location_id, lock?: true) ||
                 Repo.rollback(:not_found)

             case Ash.update(location, details,
                    action: :update_details,
                    domain: Kewkew.Business,
                    authorize?: false
                  ) do
               {:ok, location} -> location
               {:error, _error} -> Repo.rollback(:invalid_location)
             end
           end) do
        {:ok, location} -> {:ok, location}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, {:invalid_params, errors}} -> {:error, :invalid_params, errors}
      _ -> {:error, :not_found}
    end
  end

  def update_location(_user_id, _location_id, _params), do: {:error, :not_found}

  defp validate_details(params) do
    name = params |> Map.get("name", "") |> normalize_name()
    timezone = params |> Map.get("timezone", "") |> normalize_timezone()

    errors =
      []
      |> maybe_add_error(name == :missing, {:name, "Enter a location name."})
      |> maybe_add_error(
        name == :too_long,
        {:name, "Location names must be 120 characters or fewer."}
      )
      |> maybe_add_error(timezone == :missing, {:timezone, "Enter a timezone."})
      |> maybe_add_error(timezone == :invalid, {:timezone, "Choose a valid IANA timezone."})

    case errors do
      [] -> {:ok, %{name: name, timezone: timezone}}
      errors -> {:error, {:invalid_params, Enum.reverse(errors)}}
    end
  end

  defp normalize_name(name) when is_binary(name) do
    name = String.trim(name)

    cond do
      name == "" -> :missing
      String.length(name) > 120 -> :too_long
      true -> name
    end
  end

  defp normalize_name(_name), do: :missing

  defp normalize_timezone(timezone) when is_binary(timezone) do
    timezone = String.trim(timezone)

    cond do
      timezone == "" -> :missing
      timezone in @supported_timezones -> timezone
      true -> :invalid
    end
  end

  defp normalize_timezone(_timezone), do: :missing

  defp admin_organization(user_id, organization_id, opts \\ []) do
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

  defp admin_location(user_id, location_id, opts \\ []) do
    query =
      from location in Location,
        join: membership in StaffMembership,
        on: membership.organization_id == location.organization_id,
        join: organization in Organization,
        on: organization.id == location.organization_id,
        where:
          location.id == ^location_id and membership.user_id == ^user_id and
            membership.active? and membership.role == :admin,
        select: %{location: location, organization: organization},
        limit: 1

    query = if Keyword.get(opts, :lock?, false), do: lock(query, "FOR UPDATE"), else: query

    Repo.one(query)
  end

  defp maybe_add_error(errors, true, error), do: [error | errors]
  defp maybe_add_error(errors, false, _error), do: errors
end
