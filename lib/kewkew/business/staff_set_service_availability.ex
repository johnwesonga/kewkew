defmodule Kewkew.Business.StaffSetServiceAvailability do
  @moduledoc "Changes service availability for an organization administrator."

  import Ecto.Query

  alias Kewkew.Business.{Location, Service, StaffMembership}
  alias Kewkew.Queues.{Queue, Updates}
  alias Kewkew.Repo

  @doc "Activates or deactivates a service after checking organization admin access."
  def set_active(user_id, service_id, active?) when is_boolean(active?) do
    with {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, service_id} <- Ecto.UUID.cast(service_id) do
      result =
        Repo.transaction(fn ->
          query =
            from service in Service,
              join: location in Location,
              on: location.id == service.location_id,
              join: membership in StaffMembership,
              on: membership.organization_id == location.organization_id,
              where:
                service.id == ^service_id and membership.user_id == ^user_id and
                  membership.active? and membership.role == :admin,
              lock: "FOR UPDATE",
              select: service,
              limit: 1

          service = Repo.one(query) || Repo.rollback(:not_found)

          case Ash.update(service, %{active?: active?},
                 action: :set_active,
                 domain: Kewkew.Business,
                 authorize?: false,
                 return_notifications?: true
               ) do
            {:ok, updated_service, notifications} -> {updated_service, notifications}
            {:error, _error} -> Repo.rollback(:update_failed)
          end
        end)

      case result do
        {:ok, {service, notifications}} ->
          Ash.Notifier.notify(notifications)

          from(queue in Queue, where: queue.service_id == ^service.id, select: queue.id)
          |> Repo.all()
          |> Enum.each(&Updates.broadcast_queue_updated/1)

          {:ok, service}

        {:error, reason} ->
          {:error, reason}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  def set_active(_user_id, _service_id, _active?), do: {:error, :invalid_active_state}
end
