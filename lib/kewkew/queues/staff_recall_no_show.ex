defmodule Kewkew.Queues.StaffRecallNoShow do
  @moduledoc "Returns a no-show ticket to the end of its current queue session."

  import Ecto.Query

  alias Kewkew.Business.StaffAccess
  alias Kewkew.Queues.{QueueSession, Ticket, TicketEvent, Updates}
  alias Kewkew.Repo

  @doc "Requeues an authorized staff member's no-show ticket at the end of the line."
  def recall_no_show(user_id, queue_id, ticket_id)
      when is_binary(user_id) and is_binary(queue_id) and is_binary(ticket_id) do
    with %{queue: queue} <- StaffAccess.queue_for_user(user_id, queue_id),
         {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, ticket_id} <- Ecto.UUID.cast(ticket_id) do
      case Repo.transaction(fn ->
             session = lock_latest_session(queue.id) || Repo.rollback(:no_session)

             if session.status not in [:open, :paused], do: Repo.rollback(:session_closed)

             ticket =
               Repo.one(
                 from ticket in Ticket,
                   where: ticket.id == ^ticket_id and ticket.queue_session_id == ^session.id,
                   lock: "FOR UPDATE"
               ) || Repo.rollback(:not_found)

             if ticket.status != :no_show, do: Repo.rollback(:not_no_show)

             sequence = session.next_queue_sequence

             session
             |> Ecto.Changeset.change(next_queue_sequence: sequence + 1)
             |> Repo.update!()

             now = DateTime.utc_now()

             requeued_ticket =
               ticket
               |> Ecto.Changeset.change(status: :waiting, queue_sequence: sequence)
               |> Repo.update!()

             Ash.create!(
               TicketEvent,
               %{
                 ticket_id: ticket.id,
                 from_status: :no_show,
                 to_status: :waiting,
                 actor_type: :staff,
                 actor_id: user_id,
                 occurred_at: now
               },
               action: :record_transition,
               domain: Kewkew.Queues
             )

             {requeued_ticket, session.id}
           end) do
        {:ok, {ticket, session_id}} ->
          Updates.broadcast_session_updated(session_id)
          {:ok, ticket}

        {:error, reason} ->
          {:error, reason}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  def recall_no_show(_user_id, _queue_id, _ticket_id), do: {:error, :not_found}

  defp lock_latest_session(queue_id) do
    Repo.one(
      from session in QueueSession,
        where: session.queue_id == ^queue_id,
        order_by: [desc: session.opened_at, desc: session.inserted_at],
        limit: 1,
        lock: "FOR UPDATE"
    )
  end
end
