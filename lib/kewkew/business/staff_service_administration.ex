defmodule Kewkew.Business.StaffServiceAdministration do
  @moduledoc "Creates and updates services for organization administrators."

  import Ecto.Query

  alias Kewkew.Business.{Location, Service, StaffMembership}
  alias Kewkew.Repo

  @doc "Fetches a location only when the user is an administrator of its organization."
  def fetch_location(user_id, location_id) do
    with {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, location_id} <- Ecto.UUID.cast(location_id),
         %Location{} = location <- admin_location(user_id, location_id) do
      {:ok, location}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Fetches a service only when the user administers its location's organization."
  def fetch_service(user_id, service_id) do
    with {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, service_id} <- Ecto.UUID.cast(service_id),
         %{service: %Service{}} = context <- admin_service(user_id, service_id) do
      {:ok, context}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Creates a service at a location in an organization the user administers."
  def create_service(user_id, location_id, params) when is_map(params) do
    with {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, location_id} <- Ecto.UUID.cast(location_id),
         {:ok, details} <- validate_details(params) do
      case Repo.transaction(fn ->
             location =
               admin_location(user_id, location_id, lock?: true) || Repo.rollback(:not_found)

             case Ash.create(
                    Service,
                    Map.put(details, :location_id, location.id),
                    domain: Kewkew.Business,
                    authorize?: false
                  ) do
               {:ok, service} -> service
               {:error, _error} -> Repo.rollback(:invalid_service)
             end
           end) do
        {:ok, service} -> {:ok, service}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, {:invalid_params, errors}} -> {:error, :invalid_params, errors}
      _ -> {:error, :not_found}
    end
  end

  def create_service(_user_id, _location_id, _params), do: {:error, :not_found}

  @doc "Updates a service's details and visitor instructions without changing its location."
  def update_service(user_id, service_id, params) when is_map(params) do
    with {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, service_id} <- Ecto.UUID.cast(service_id),
         {:ok, details} <- validate_details(params) do
      case Repo.transaction(fn ->
             %{service: service} =
               admin_service(user_id, service_id, lock?: true) || Repo.rollback(:not_found)

             case Ash.update(service, details,
                    action: :update_details,
                    domain: Kewkew.Business,
                    authorize?: false
                  ) do
               {:ok, updated_service} -> updated_service
               {:error, _error} -> Repo.rollback(:invalid_service)
             end
           end) do
        {:ok, service} -> {:ok, service}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, {:invalid_params, errors}} -> {:error, :invalid_params, errors}
      _ -> {:error, :not_found}
    end
  end

  def update_service(_user_id, _service_id, _params), do: {:error, :not_found}

  defp validate_details(params) do
    name = params |> Map.get("name", "") |> normalize_name()
    description = params |> Map.get("description", "") |> normalize_description()

    visitor_instructions =
      params |> Map.get("visitor_instructions", "") |> normalize_visitor_instructions()

    errors =
      []
      |> maybe_add_error(name == :missing, {:name, "Enter a service name."})
      |> maybe_add_error(
        name == :too_long,
        {:name, "Service names must be 120 characters or fewer."}
      )
      |> maybe_add_error(
        description == :too_long,
        {:description, "Descriptions must be 1,000 characters or fewer."}
      )
      |> maybe_add_error(
        visitor_instructions == :too_long,
        {:visitor_instructions, "Visitor instructions must be 500 characters or fewer."}
      )

    case errors do
      [] ->
        {:ok,
         %{
           name: name,
           description: description,
           visitor_instructions:
             if(visitor_instructions == :missing, do: nil, else: visitor_instructions)
         }}

      errors ->
        {:error, {:invalid_params, Enum.reverse(errors)}}
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

  defp normalize_description(description) when is_binary(description) do
    description = String.trim(description)

    cond do
      description == "" -> nil
      String.length(description) > 1000 -> :too_long
      true -> description
    end
  end

  defp normalize_description(_description), do: nil

  defp normalize_visitor_instructions(instructions) when is_binary(instructions) do
    instructions = String.trim(instructions)

    cond do
      instructions == "" -> :missing
      String.length(instructions) > 500 -> :too_long
      true -> instructions
    end
  end

  defp normalize_visitor_instructions(_instructions), do: :missing

  defp admin_location(user_id, location_id, opts \\ []) do
    query =
      from location in Location,
        join: membership in StaffMembership,
        on: membership.organization_id == location.organization_id,
        where:
          location.id == ^location_id and membership.user_id == ^user_id and
            membership.active? and membership.role == :admin,
        limit: 1

    query = if Keyword.get(opts, :lock?, false), do: lock(query, "FOR UPDATE"), else: query

    Repo.one(query)
  end

  defp admin_service(user_id, service_id, opts \\ []) do
    query =
      from service in Service,
        join: location in Location,
        on: location.id == service.location_id,
        join: membership in StaffMembership,
        on: membership.organization_id == location.organization_id,
        where:
          service.id == ^service_id and membership.user_id == ^user_id and
            membership.active? and membership.role == :admin,
        select: %{service: service, location: location},
        limit: 1

    query = if Keyword.get(opts, :lock?, false), do: lock(query, "FOR UPDATE"), else: query

    Repo.one(query)
  end

  defp maybe_add_error(errors, true, error), do: [error | errors]
  defp maybe_add_error(errors, false, _error), do: errors
end
