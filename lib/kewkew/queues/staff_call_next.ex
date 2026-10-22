defmodule Kewkew.Queues.StaffCallNext do
  @moduledoc "Calls the earliest waiting visitor for an authorized staff member."

  import Ecto.Query

  alias Kewkew.Business.StaffAccess
  alias Kewkew.Queues.{QueueSession, Ticket, TicketEvent, Updates}
  alias Kewkew.Repo

  @doc "Moves the earliest waiting ticket to called and records the staff transition atomically."
  def call_next(user_id, queue_id) when is_binary(user_id) and is_binary(queue_id) do
    with %{queue: queue} <- StaffAccess.queue_for_user(user_id, queue_id),
         {:ok, user_id} <- Ecto.UUID.cast(user_id) do
      case Repo.transaction(fn ->
             session = lock_latest_session(queue.id) || Repo.rollback(:no_session)
             ticket = lock_next_waiting_ticket(session.id) || Repo.rollback(:no_waiting)
             now = DateTime.utc_now()

             called_ticket =
               ticket
               |> Ecto.Changeset.change(status: :called, called_at: now)
               |> Repo.update!()

             Ash.create!(
               TicketEvent,
               %{
                 ticket_id: ticket.id,
                 from_status: :waiting,
                 to_status: :called,
                 actor_type: :staff,
                 actor_id: user_id,
                 occurred_at: now
               },
               action: :record_transition,
               domain: Kewkew.Queues
             )

             {called_ticket, session.id}
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

  def call_next(_user_id, _queue_id), do: {:error, :not_found}

  defp lock_latest_session(queue_id) do
    Repo.one(
      from session in QueueSession,
        where: session.queue_id == ^queue_id,
        order_by: [desc: session.opened_at, desc: session.inserted_at],
        limit: 1,
        lock: "FOR UPDATE"
    )
  end

  defp lock_next_waiting_ticket(session_id) do
    Repo.one(
      from ticket in Ticket,
        where: ticket.queue_session_id == ^session_id and ticket.status == :waiting,
        order_by: [asc: ticket.queue_sequence],
        limit: 1,
        lock: "FOR UPDATE"
    )
  end
end
