defmodule Kewkew.Business.StaffSetLocationAvailability do
  @moduledoc "Changes location availability for an organization administrator."

  import Ecto.Query

  alias Kewkew.Business.{Location, StaffMembership}
  alias Kewkew.Queues.{Queue, Updates}
  alias Kewkew.Repo

  @doc "Activates or deactivates a location after checking organization admin access."
  def set_active(user_id, location_id, active?) when is_boolean(active?) do
    with {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, location_id} <- Ecto.UUID.cast(location_id) do
      result =
        Repo.transaction(fn ->
          query =
            from location in Location,
              join: membership in StaffMembership,
              on: membership.organization_id == location.organization_id,
              where:
                location.id == ^location_id and membership.user_id == ^user_id and
                  membership.active? and membership.role == :admin,
              lock: "FOR UPDATE",
              select: location,
              limit: 1

          location = Repo.one(query) || Repo.rollback(:not_found)

          case Ash.update(location, %{active?: active?},
                 action: :set_active,
                 domain: Kewkew.Business,
                 authorize?: false,
                 return_notifications?: true
               ) do
            {:ok, updated_location, notifications} -> {updated_location, notifications}
            {:error, _error} -> Repo.rollback(:update_failed)
          end
        end)

      case result do
        {:ok, {location, notifications}} ->
          Ash.Notifier.notify(notifications)

          from(queue in Queue, where: queue.location_id == ^location.id, select: queue.id)
          |> Repo.all()
          |> Enum.each(&Updates.broadcast_queue_updated/1)

          {:ok, location}

        {:error, reason} ->
          {:error, reason}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  def set_active(_user_id, _location_id, _active?), do: {:error, :invalid_active_state}
end
