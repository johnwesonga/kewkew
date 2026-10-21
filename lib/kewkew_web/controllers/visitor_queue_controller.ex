defmodule KewkewWeb.VisitorQueueController do
  use KewkewWeb, :controller

  def show(conn, %{"slug" => slug}) do
    case Kewkew.Queues.PublicLookup.fetch_queue(slug) do
      {:ok, nil} ->
        conn
        |> put_status(:not_found)
        |> render(:unavailable, page_title: "Queue unavailable")

      {:ok, %{queue: queue, session: session, active_ticket_count: active_ticket_count}} ->
        conn
        |> render(:show,
          page_title: queue.name,
          queue: queue,
          location: queue.location,
          service: queue.service,
          availability: availability(session, active_ticket_count, queue.max_active_tickets)
        )

      {:error, _error} ->
        conn
        |> put_status(:not_found)
        |> render(:unavailable, page_title: "Queue unavailable")
    end
  end

  defp availability(%{status: :open}, count, max) do
    if max && count >= max do
      %{
        label: "Queue is full",
        state: :full,
        message: "This queue has reached its current capacity. Please ask staff for help."
      }
    else
      %{label: "Open now", state: :open, message: "You can join this queue now."}
    end
  end

  defp availability(%{status: :paused}, _count, _max),
    do: %{
      label: "Temporarily paused",
      state: :paused,
      message: "Joining is temporarily paused. Please check again shortly."
    }

  defp availability(_session, _count, _max),
    do: %{
      label: "Not accepting visitors",
      state: :closed,
      message: "This queue is currently closed. Please check back later."
    }
end
