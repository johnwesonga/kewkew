defmodule Kewkew.Queues.StaffCreateQueue do
  @moduledoc "Creates queues for authorized organization administrators."

  import Ecto.Query

  alias Kewkew.Business.{Service, StaffAccess}
  alias Kewkew.Queues.Queue
  alias Kewkew.Repo

  @doc "Lists active services at a location the staff member administers."
  def services_for_location(user_id, location_id) do
    case StaffAccess.admin_location_for_user(user_id, location_id) do
      nil ->
        {:error, :not_found}

      location ->
        services =
          Repo.all(
            from service in Service,
              where: service.location_id == ^location.id and service.active?,
              order_by: [asc: service.name]
          )

        {:ok, %{location: location, services: services}}
    end
  end

  @doc "Creates an authorized administrator's queue with server-validated settings."
  def create_queue(user_id, location_id, params)
      when is_binary(user_id) and is_binary(location_id) and is_map(params) do
    with {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, location_id} <- Ecto.UUID.cast(location_id),
         {:ok, queue_params} <- validate_params(params) do
      case Repo.transaction(fn ->
             location =
               StaffAccess.admin_location_for_user(user_id, location_id) ||
                 Repo.rollback(:not_found)

             service =
               Repo.one(
                 from service in Service,
                   where:
                     service.id == ^queue_params.service_id and
                       service.location_id == ^location.id and service.active?
               ) || Repo.rollback(:invalid_service)

             attrs = %{
               name: queue_params.name,
               public_slug: public_slug(queue_params.name),
               identity_policy: queue_params.identity_policy,
               max_active_tickets: queue_params.max_active_tickets,
               location_id: location.id,
               service_id: service.id
             }

             case Ash.create(Queue, attrs, domain: Kewkew.Queues, authorize?: false) do
               {:ok, queue} -> queue
               {:error, _error} -> Repo.rollback(:invalid_queue)
             end
           end) do
        {:ok, queue} -> {:ok, queue}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :invalid_params, errors} -> {:error, :invalid_params, errors}
      _ -> {:error, :not_found}
    end
  end

  def create_queue(_user_id, _location_id, _params), do: {:error, :not_found}

  defp validate_params(params) do
    service_id = Map.get(params, "service_id", "")
    service_id = Ecto.UUID.cast(service_id)

    case {validate_configuration(params), service_id} do
      {{:ok, configuration}, {:ok, service_id}} ->
        {:ok, Map.put(configuration, :service_id, service_id)}

      {configuration_result, service_id_result} ->
        errors =
          case configuration_result do
            {:error, :invalid_params, errors} -> errors
            {:ok, _configuration} -> []
          end

        service_id_invalid? =
          case service_id_result do
            {:ok, _service_id} -> false
            :error -> true
          end

        errors =
          if service_id_invalid? do
            [{:service_id, "Choose a service at this location."} | errors]
          else
            errors
          end

        {:error, :invalid_params, errors}
    end
  end

  @doc "Validates editable queue configuration shared by create and update flows."
  def validate_configuration(params) when is_map(params) do
    name = params |> Map.get("name", "") |> normalize_name()
    identity_policy = identity_policy(Map.get(params, "identity_policy"))
    capacity = capacity(Map.get(params, "max_active_tickets", ""))

    errors =
      []
      |> maybe_add_error(name == :missing, {:name, "Enter a queue name."})
      |> maybe_add_error(
        name == :too_long,
        {:name, "Queue names must be 100 characters or fewer."}
      )
      |> maybe_add_error(
        is_nil(identity_policy),
        {:identity_policy, "Choose a visitor identity policy."}
      )
      |> maybe_add_error(
        capacity == :invalid,
        {:max_active_tickets, "Enter a positive whole number or leave capacity blank."}
      )

    case errors do
      [] ->
        {:ok,
         %{
           name: name,
           identity_policy: identity_policy,
           max_active_tickets: if(capacity == :unlimited, do: nil, else: capacity)
         }}

      errors ->
        {:error, :invalid_params, errors}
    end
  end

  def validate_configuration(_params),
    do: {:error, :invalid_params, [{:queue, "Invalid queue details."}]}

  defp normalize_name(name) when is_binary(name) do
    name = String.trim(name)

    cond do
      name == "" -> :missing
      String.length(name) > 100 -> :too_long
      true -> name
    end
  end

  defp normalize_name(_name), do: :missing

  defp identity_policy("anonymous"), do: :anonymous
  defp identity_policy("name_required"), do: :name_required
  defp identity_policy(_identity_policy), do: nil

  defp capacity(nil), do: :unlimited
  defp capacity(""), do: :unlimited

  defp capacity(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> number
      _ -> :invalid
    end
  end

  defp capacity(_value), do: :invalid

  defp maybe_add_error(errors, true, error), do: [error | errors]
  defp maybe_add_error(errors, false, _error), do: errors

  defp public_slug(name) do
    base =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")

    base = if base == "", do: "queue", else: base
    suffix = :crypto.strong_rand_bytes(5) |> Base.encode16(case: :lower)
    "#{base}-#{suffix}"
  end
end
