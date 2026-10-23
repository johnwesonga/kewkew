defmodule Kewkew.Queues.StaffOpenQueueSession do
  @moduledoc "Opens a new operating session for an authorized queue staff member."

  import Ecto.Query

  alias Kewkew.Business.StaffAccess
  alias Kewkew.Queues.{Queue, QueueSession, Updates}
  alias Kewkew.Repo

  @doc "Opens a session if the staff member has access and all queue services are active."
  def open_session(user_id, queue_id)
      when is_binary(user_id) and is_binary(queue_id) do
    with {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, queue_id} <- Ecto.UUID.cast(queue_id) do
      case Repo.transaction(fn ->
             Repo.one(
               from queue in Queue,
                 where: queue.id == ^queue_id,
                 lock: "FOR UPDATE"
             ) || Repo.rollback(:not_found)

             %{queue: queue, location: location, service: service} =
               StaffAccess.queue_for_user(user_id, queue_id) || Repo.rollback(:not_found)

             ensure_active!(queue, location, service)

             if Repo.exists?(
                  from session in QueueSession,
                    where:
                      session.queue_id == ^queue.id and
                        session.status in [:open, :paused]
                ) do
               Repo.rollback(:session_already_open)
             end

             case Ash.create(
                    QueueSession,
                    %{queue_id: queue.id, status: :open},
                    action: :create,
                    domain: Kewkew.Queues,
                    authorize?: false
                  ) do
               {:ok, session} -> session
               {:error, _error} -> Repo.rollback(:session_already_open)
             end
           end) do
        {:ok, session} ->
          Updates.broadcast_queue_updated(queue_id)
          {:ok, session}

        {:error, reason} ->
          {:error, reason}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  def open_session(_user_id, _queue_id), do: {:error, :not_found}

  defp ensure_active!(queue, location, service) do
    cond do
      not queue.active? -> Repo.rollback(:queue_inactive)
      not location.active? -> Repo.rollback(:location_inactive)
      not service.active? -> Repo.rollback(:service_inactive)
      true -> :ok
    end
  end
end
