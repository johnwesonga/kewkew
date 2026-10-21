defmodule Kewkew.Queues.PublicLookup do
  @moduledoc "Read-only lookups used to render public queue pages."

  require Ash.Query

  alias Kewkew.Business.Location
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
end
