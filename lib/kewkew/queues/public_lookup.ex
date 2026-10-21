defmodule Kewkew.Queues.PublicLookup do
  @moduledoc "Read-only lookups used to render public queue pages."

  require Ash.Query

  alias Kewkew.Business.Location
  alias Kewkew.Queues.{Queue, QueueSession, Ticket, TrackingCredential}

  def fetch_queue(slug) when is_binary(slug) do
    Queue
    |> Ash.Query.for_read(:by_public_slug, %{slug: slug})
    |> Ash.read_one(domain: Kewkew.Queues)
    |> case do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, queue} ->
        fetch_latest_session(queue)

      error ->
        error
    end
  end

  def fetch_queue(_slug), do: {:ok, nil}

  def list_location_queues(location_id) when is_binary(location_id) do
    Location
    |> Ash.Query.filter(id == ^location_id)
    |> Ash.read_one(domain: Kewkew.Business)
    |> case do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, %{active?: true} = location} ->
        queues =
          Queue
          |> Ash.Query.filter(location_id == ^location.id)
          |> Ash.Query.load(:service)
          |> Ash.read!(domain: Kewkew.Queues)
          |> Enum.filter(& &1.service.active?)
          |> Enum.map(&queue_with_session/1)

        {:ok, %{location: location, queues: queues}}

      {:ok, _inactive_location} ->
        {:ok, nil}

      error ->
        error
    end
  end

  def list_location_queues(_location_id), do: {:ok, nil}

  def fetch_tracking_ticket(token) when is_binary(token) do
    token_digest = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

    with {:ok, %TrackingCredential{} = credential} <- find_credential(token_digest),
         :ok <- credential_is_valid(credential),
         {:ok, %Ticket{} = ticket} <- find_ticket(credential.ticket_id),
         {:ok, %QueueSession{} = session} <- find_session(ticket.queue_session_id),
         {:ok, %Queue{} = queue} <- find_queue(session.queue_id) do
      {:ok,
       %{
         ticket: ticket,
         session: session,
         queue: queue,
         location: queue.location,
         service: queue.service
       }}
    else
      {:ok, nil} -> {:ok, nil}
      {:error, _error} -> {:ok, nil}
      _ -> {:ok, nil}
    end
  end

  def fetch_tracking_ticket(_token), do: {:ok, nil}

  defp fetch_latest_session(queue) do
    QueueSession
    |> Ash.Query.for_read(:latest_for_queue, %{queue_id: queue.id})
    |> Ash.read_one(domain: Kewkew.Queues)
    |> case do
      {:ok, session} when not is_nil(session) ->
        if queue.location.active? and queue.service.active? do
          {:ok,
           %{queue: queue, session: session, active_ticket_count: active_ticket_count(session)}}
        else
          {:ok, nil}
        end

      {:ok, nil} ->
        if queue.location.active? and queue.service.active? do
          {:ok, %{queue: queue, session: nil, active_ticket_count: 0}}
        else
          {:ok, nil}
        end

      error ->
        error
    end
  end

  defp active_ticket_count(session) do
    Ticket
    |> Ash.Query.filter(
      queue_session_id == ^session.id and status in [:waiting, :called, :serving]
    )
    |> Ash.count!(domain: Kewkew.Queues)
  end

  defp queue_with_session(queue) do
    session =
      QueueSession
      |> Ash.Query.for_read(:latest_for_queue, %{queue_id: queue.id})
      |> Ash.read_one!(domain: Kewkew.Queues)

    %{
      queue: queue,
      session: session,
      active_ticket_count: if(session, do: active_ticket_count(session), else: 0)
    }
  end

  defp find_credential(token_digest) do
    TrackingCredential
    |> Ash.Query.filter(token_digest == ^token_digest)
    |> Ash.read_one(domain: Kewkew.Queues)
  end

  defp find_ticket(ticket_id) do
    Ticket
    |> Ash.Query.filter(id == ^ticket_id)
    |> Ash.read_one(domain: Kewkew.Queues)
  end

  defp find_session(session_id) do
    QueueSession
    |> Ash.Query.filter(id == ^session_id)
    |> Ash.read_one(domain: Kewkew.Queues)
  end

  defp find_queue(queue_id) do
    Queue
    |> Ash.Query.filter(id == ^queue_id)
    |> Ash.Query.load([:location, :service])
    |> Ash.read_one(domain: Kewkew.Queues)
  end

  defp credential_is_valid(%TrackingCredential{revoked_at: revoked_at})
       when not is_nil(revoked_at),
       do: {:error, :revoked}

  defp credential_is_valid(%TrackingCredential{expires_at: expires_at})
       when not is_nil(expires_at) do
    if DateTime.compare(expires_at, DateTime.utc_now()) == :gt,
      do: :ok,
      else: {:error, :expired}
  end

  defp credential_is_valid(_credential), do: :ok
end
