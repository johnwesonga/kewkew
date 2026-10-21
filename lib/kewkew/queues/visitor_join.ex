defmodule Kewkew.Queues.VisitorJoin do
  @moduledoc "Creates anonymous visitor tickets and private tracking credentials."

  import Ecto.Query

  require Ash.Query

  alias Kewkew.Queues
  alias Kewkew.Queues.{Queue, QueueSession, Ticket, TicketEvent, TrackingCredential}
  alias Kewkew.Repo

  def join_anonymous(slug, attempt_token) when is_binary(slug) and is_binary(attempt_token) do
    with :ok <- validate_attempt_token(attempt_token) do
      token_digest = digest(attempt_token)

      case Repo.transaction(fn ->
             case existing_ticket(token_digest) do
               %Ticket{} = ticket ->
                 %{ticket: ticket, tracking_token: attempt_token}

               nil ->
                 create_ticket(slug, attempt_token, token_digest)
             end
           end) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def join_anonymous(_slug, _attempt_token), do: {:error, :invalid_attempt}

  defp create_ticket(slug, tracking_token, token_digest) do
    queue =
      Queue
      |> Ash.Query.for_read(:by_public_slug, %{slug: slug})
      |> Ash.read_one!(domain: Queues)

    if is_nil(queue) or not queue.location.active? or not queue.service.active? do
      Repo.rollback(:unavailable)
    end

    if queue.identity_policy != :anonymous do
      Repo.rollback(:name_required)
    end

    session =
      Repo.one(
        from session in QueueSession,
          where: session.queue_id == ^queue.id and session.status in [:open, :paused],
          order_by: [desc: session.opened_at],
          limit: 1,
          lock: "FOR UPDATE"
      )

    cond do
      is_nil(session) ->
        Repo.rollback(:unavailable)

      session.status != :open ->
        Repo.rollback(:unavailable)

      ticket = existing_ticket(token_digest) ->
        %{ticket: ticket, tracking_token: tracking_token}

      queue_is_full?(queue, session) ->
        Repo.rollback(:full)

      true ->
        create_ticket_records(session, tracking_token, token_digest)
    end
  end

  defp queue_is_full?(%{max_active_tickets: nil}, _session), do: false

  defp queue_is_full?(queue, session) do
    active_count =
      Ticket
      |> Ash.Query.filter(
        queue_session_id == ^session.id and status in [:waiting, :called, :serving]
      )
      |> Ash.count!(domain: Queues)

    active_count >= queue.max_active_tickets
  end

  defp create_ticket_records(session, tracking_token, token_digest) do
    ticket_number = session.next_ticket_number
    queue_sequence = session.next_queue_sequence

    session
    |> Ecto.Changeset.change(
      next_ticket_number: ticket_number + 1,
      next_queue_sequence: queue_sequence + 1
    )
    |> Repo.update!()

    ticket =
      Ash.create!(
        Ticket,
        %{
          queue_session_id: session.id,
          ticket_number: ticket_number,
          queue_sequence: queue_sequence
        },
        action: :join_anonymous,
        domain: Queues
      )

    Ash.create!(
      TicketEvent,
      %{
        ticket_id: ticket.id,
        to_status: :waiting,
        actor_type: :visitor
      },
      action: :record_transition,
      domain: Queues
    )

    Ash.create!(
      TrackingCredential,
      %{ticket_id: ticket.id, token_digest: token_digest},
      action: :create_for_ticket,
      domain: Queues
    )

    %{ticket: ticket, tracking_token: tracking_token}
  end

  defp existing_ticket(token_digest) do
    case TrackingCredential
         |> Ash.Query.filter(token_digest == ^token_digest)
         |> Ash.read_one!(domain: Queues) do
      nil ->
        nil

      credential ->
        Ticket
        |> Ash.Query.filter(id == ^credential.ticket_id)
        |> Ash.read_one!(domain: Queues)
    end
  end

  defp validate_attempt_token(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, bytes} when byte_size(bytes) == 32 -> :ok
      _ -> {:error, :invalid_attempt}
    end
  end

  defp digest(token), do: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
end
