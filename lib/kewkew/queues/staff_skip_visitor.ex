defmodule Kewkew.Queues.StaffSkipVisitor do
  @moduledoc "Marks a called visitor as a no-show for an authorized staff member."

  import Ecto.Query

  alias Kewkew.Business.StaffAccess
  alias Kewkew.Queues.{BrowserTicketClaims, QueueSession, Ticket, TicketEvent, Updates}
  alias Kewkew.Repo

  @doc "Moves a called ticket to no_show and records its staff transition atomically."
  def skip_visitor(user_id, queue_id, ticket_id)
      when is_binary(user_id) and is_binary(queue_id) and is_binary(ticket_id) do
    with %{queue: queue} <- StaffAccess.queue_for_user(user_id, queue_id),
         {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, ticket_id} <- Ecto.UUID.cast(ticket_id) do
      case Repo.transaction(fn ->
             session = lock_latest_session(queue.id) || Repo.rollback(:no_session)

             ticket =
               Repo.one(
                 from ticket in Ticket,
                   where: ticket.id == ^ticket_id and ticket.queue_session_id == ^session.id,
                   lock: "FOR UPDATE"
               ) || Repo.rollback(:not_found)

             if ticket.status != :called, do: Repo.rollback(:not_called)

             now = DateTime.utc_now()

             skipped_ticket =
               ticket
               |> Ecto.Changeset.change(status: :no_show)
               |> Repo.update!()

             Ash.create!(
               TicketEvent,
               %{
                 ticket_id: ticket.id,
                 from_status: :called,
                 to_status: :no_show,
                 actor_type: :staff,
                 actor_id: user_id,
                 occurred_at: now
               },
               action: :record_transition,
               domain: Kewkew.Queues
             )

             BrowserTicketClaims.release_for_ticket(ticket.id)

             {skipped_ticket, session.id}
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

  def skip_visitor(_user_id, _queue_id, _ticket_id), do: {:error, :not_found}

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
