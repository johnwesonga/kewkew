defmodule Kewkew.Queues.StaffSetQueueAvailability do
  @moduledoc "Changes whether an organization administrator's queue accepts visitors."

  import Ecto.Query

  alias Kewkew.Business.{Location, StaffMembership}
  alias Kewkew.Queues.Queue
  alias Kewkew.Repo

  @doc "Activates or deactivates a queue after checking organization administrator access."
  def set_active(user_id, queue_id, active?) when is_boolean(active?) do
    with {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, queue_id} <- Ecto.UUID.cast(queue_id) do
      Repo.transaction(fn ->
        query =
          from queue in Queue,
            join: location in Location,
            on: location.id == queue.location_id,
            join: membership in StaffMembership,
            on: membership.organization_id == location.organization_id,
            where:
              queue.id == ^queue_id and membership.user_id == ^user_id and
                membership.active? and membership.role == :admin,
            lock: "FOR UPDATE",
            select: queue,
            limit: 1

        queue = Repo.one(query)

        queue = queue || Repo.rollback(:not_found)

        case Ash.update(queue, %{active?: active?},
               action: :set_active,
               domain: Kewkew.Queues,
               authorize?: false
             ) do
          {:ok, updated_queue} -> updated_queue
          {:error, _error} -> Repo.rollback(:update_failed)
        end
      end)
      |> case do
        {:ok, queue} -> {:ok, queue}
        {:error, reason} -> {:error, reason}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  def set_active(_user_id, _queue_id, _active?), do: {:error, :invalid_active_state}
end
