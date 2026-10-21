defmodule Kewkew.Queues.PublicLookup do
  @moduledoc "Read-only lookups used to render public queue pages."

  require Ash.Query

  alias Kewkew.Queues.{Queue, QueueSession, Ticket}

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
end
