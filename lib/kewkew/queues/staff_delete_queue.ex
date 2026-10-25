defmodule Kewkew.Queues.StaffDeleteQueue do
  @moduledoc "Deletes an unused queue for an administrator of its organization."

  import Ecto.Query

  alias Kewkew.Business.{Location, StaffMembership}
  alias Kewkew.Queues.{Queue, QueueSchedule, QueueSession}
  alias Kewkew.Repo

  def delete_queue(user_id, queue_id) when is_binary(user_id) and is_binary(queue_id) do
    with {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, queue_id} <- Ecto.UUID.cast(queue_id) do
      Repo.transaction(fn ->
        queue =
          Repo.one(
            from queue in Queue,
              where: queue.id == ^queue_id,
              lock: "FOR UPDATE"
          ) || Repo.rollback(:not_found)

        authorized? =
          Repo.exists?(
            from authorized_queue in Queue,
              join: location in Location,
              on: location.id == authorized_queue.location_id,
              join: membership in StaffMembership,
              on: membership.organization_id == location.organization_id,
              where:
                authorized_queue.id == ^queue.id and membership.user_id == ^user_id and
                  membership.active? and membership.role == :admin
          )

        unless authorized?, do: Repo.rollback(:not_found)

        if Repo.exists?(from session in QueueSession, where: session.queue_id == ^queue.id) do
          Repo.rollback(:has_history)
        end

        if schedule =
             Repo.one(from schedule in QueueSchedule, where: schedule.queue_id == ^queue.id) do
          case Ash.destroy(schedule,
                 action: :delete,
                 domain: Kewkew.Queues,
                 authorize?: false
               ) do
            :ok -> :ok
            {:ok, _schedule} -> :ok
            {:error, _error} -> Repo.rollback(:delete_failed)
          end
        end

        case Ash.destroy(queue,
               action: :delete,
               domain: Kewkew.Queues,
               authorize?: false
             ) do
          :ok -> queue
          {:ok, _queue} -> queue
          {:error, _error} -> Repo.rollback(:delete_failed)
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

  def delete_queue(_user_id, _queue_id), do: {:error, :not_found}
end
