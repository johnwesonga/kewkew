defmodule Kewkew.Queues.VisitorJoin do
  @moduledoc "Creates anonymous visitor tickets and private tracking credentials."

  import Ecto.Query

  require Ash.Query

  alias Kewkew.Queues
  alias Kewkew.Queues.{Queue, QueueSession, Ticket, TicketEvent, TrackingCredential, Updates}
  alias Kewkew.Repo

  def join_anonymous(slug, attempt_token) when is_binary(slug) and is_binary(attempt_token) do
    perform_join(slug, attempt_token, %{}, :anonymous)
  end

  def join_anonymous(_slug, _attempt_token), do: {:error, :invalid_attempt}

  def join_visitor(slug, attempt_token, params)
      when is_binary(slug) and is_binary(attempt_token) and is_map(params) do
    perform_join(slug, attempt_token, params, :any)
  end

  def join_visitor(_slug, _attempt_token, _params), do: {:error, :invalid_attempt}

  defp perform_join(slug, attempt_token, params, expected_policy) do
    with :ok <- validate_attempt_token(attempt_token) do
      token_digest = digest(attempt_token)

      case Repo.transaction(fn ->
             case existing_ticket(token_digest) do
               %Ticket{} = ticket ->
                 %{ticket: ticket, tracking_token: attempt_token}

               nil ->
                 create_ticket(slug, attempt_token, token_digest, params, expected_policy)
             end
           end) do
        {:ok, result} ->
          Updates.broadcast_session_updated(result.ticket.queue_session_id)
          {:ok, result}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp create_ticket(slug, tracking_token, token_digest, params, expected_policy) do
    queue = fetch_queue_for_join(slug)

    if is_nil(queue) or not queue.active? or not queue.location.active? or
         not queue.service.active? do
      Repo.rollback(:unavailable)
    end

    if expected_policy == :anonymous and queue.identity_policy != :anonymous,
      do: Repo.rollback(:name_required)

    names = names_for_policy(queue.identity_policy, params)

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
        create_ticket_records(session, tracking_token, token_digest, names)
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

  defp fetch_queue_for_join(slug) do
    case Repo.one(from queue in Queue, where: queue.public_slug == ^slug, lock: "FOR UPDATE") do
      nil ->
        nil

      _queue ->
        Queue
        |> Ash.Query.for_read(:by_public_slug, %{slug: slug})
        |> Ash.read_one!(domain: Queues)
    end
  end

  defp create_ticket_records(session, tracking_token, token_digest, names) do
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
          queue_sequence: queue_sequence,
          first_name: names.first_name,
          last_name: names.last_name
        },
        action: :join_visitor,
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

  defp names_for_policy(:anonymous, _params), do: %{first_name: nil, last_name: nil}

  defp names_for_policy(:name_required, params) do
    first_name = normalize_name(Map.get(params, "first_name"))
    last_name = normalize_name(Map.get(params, "last_name"))

    cond do
      first_name == :missing -> Repo.rollback(:first_name_required)
      last_name == :missing -> Repo.rollback(:last_name_required)
      first_name == :too_long -> Repo.rollback(:first_name_too_long)
      last_name == :too_long -> Repo.rollback(:last_name_too_long)
      true -> %{first_name: first_name, last_name: last_name}
    end
  end

  defp normalize_name(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" -> :missing
      String.length(value) > 100 -> :too_long
      true -> value
    end
  end

  defp normalize_name(_value), do: :missing

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
