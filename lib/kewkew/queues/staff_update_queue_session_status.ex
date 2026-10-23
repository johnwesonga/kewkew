defmodule Kewkew.Queues.StaffUpdateQueueSessionStatus do
  @moduledoc "Pauses or resumes the current session for an authorized queue operator."

  import Ecto.Query

  alias Kewkew.Business.StaffAccess
  alias Kewkew.Queues.{Queue, QueueSession, Updates}
  alias Kewkew.Repo

  @doc "Pauses an open session while preserving its tickets and sequence."
  def pause(user_id, queue_id), do: transition(user_id, queue_id, :open, :paused)

  @doc "Resumes a paused session without changing its tickets or sequence."
  def resume(user_id, queue_id), do: transition(user_id, queue_id, :paused, :open)

  defp transition(user_id, queue_id, from_status, to_status)
       when is_binary(user_id) and is_binary(queue_id) do
    with {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, queue_id} <- Ecto.UUID.cast(queue_id) do
      case Repo.transaction(fn ->
             Repo.one(
               from queue in Queue,
                 where: queue.id == ^queue_id,
                 lock: "FOR UPDATE"
             ) || Repo.rollback(:not_found)

             %{queue: queue} =
               StaffAccess.queue_for_user(user_id, queue_id) ||
                 Repo.rollback(:not_found)

             session = lock_current_session(queue.id) || Repo.rollback(:no_active_session)

             if session.status != from_status do
               Repo.rollback(:invalid_transition)
             end

             session
             |> Ecto.Changeset.change(status: to_status)
             |> Repo.update!()
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

  defp transition(_user_id, _queue_id, _from_status, _to_status), do: {:error, :not_found}

  defp lock_current_session(queue_id) do
    Repo.one(
      from session in QueueSession,
        where: session.queue_id == ^queue_id and session.status in [:open, :paused],
        order_by: [desc: session.opened_at, desc: session.inserted_at],
        limit: 1,
        lock: "FOR UPDATE"
    )
  end
end
