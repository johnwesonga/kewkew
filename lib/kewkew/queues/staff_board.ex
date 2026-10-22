defmodule Kewkew.Queues.StaffBoard do
  @moduledoc "Returns queue board data after checking the staff member's location access."

  import Ecto.Query

  alias Kewkew.Business.StaffAccess
  alias Kewkew.Queues.{QueueSession, Ticket}
  alias Kewkew.Repo

  @active_ticket_statuses [:waiting, :called, :serving]

  @doc "Loads a queue, its latest session, and active tickets for an authorized staff member."
  def fetch_queue(user_id, queue_id) when is_binary(user_id) and is_binary(queue_id) do
    case StaffAccess.queue_for_user(user_id, queue_id) do
      nil ->
        {:error, :not_found}

      %{queue: queue} = data ->
        session =
          Repo.one(
            from session in QueueSession,
              where: session.queue_id == ^queue.id,
              order_by: [desc: session.opened_at, desc: session.inserted_at],
              limit: 1
          )

        tickets =
          case session do
            nil ->
              []

            session ->
              Repo.all(
                from ticket in Ticket,
                  where:
                    ticket.queue_session_id == ^session.id and
                      ticket.status in ^@active_ticket_statuses,
                  order_by: [asc: ticket.queue_sequence]
              )
          end

        {:ok, Map.merge(data, %{session: session, tickets: tickets})}
    end
  end

  def fetch_queue(_user_id, _queue_id), do: {:error, :not_found}
end
