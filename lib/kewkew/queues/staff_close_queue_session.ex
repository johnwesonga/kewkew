defmodule Kewkew.Queues.StaffCloseQueueSession do
  @moduledoc "Closes an authorized queue session after all active tickets are resolved."

  import Ecto.Query

  alias Kewkew.Business.StaffAccess
  alias Kewkew.Queues.{BrowserTicketClaims, Queue, QueueSession, Ticket, Updates}
  alias Kewkew.Repo

  @active_ticket_statuses [:waiting, :called, :serving]

  @doc "Closes the current session when no visitors are waiting, called, or being served."
  def close_session(user_id, queue_id)
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
               StaffAccess.queue_for_user(user_id, queue_id) || Repo.rollback(:not_found)

             session = lock_current_session(queue.id) || Repo.rollback(:no_active_session)

             if has_active_tickets?(session.id) do
               Repo.rollback(:active_tickets_remain)
             end

             closed_session =
               session
               |> Ecto.Changeset.change(status: :closed, closed_at: DateTime.utc_now())
               |> Repo.update!()

             BrowserTicketClaims.release_for_session(session.id)
             closed_session
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

  def close_session(_user_id, _queue_id), do: {:error, :not_found}

  defp lock_current_session(queue_id) do
    Repo.one(
      from session in QueueSession,
        where: session.queue_id == ^queue_id and session.status in [:open, :paused],
        order_by: [desc: session.opened_at, desc: session.inserted_at],
        limit: 1,
        lock: "FOR UPDATE"
    )
  end

  defp has_active_tickets?(session_id) do
    Repo.exists?(
      from ticket in Ticket,
        where:
          ticket.queue_session_id == ^session_id and ticket.status in ^@active_ticket_statuses
    )
  end
end
