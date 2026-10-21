defmodule KewkewWeb.VisitorQueueController do
  use KewkewWeb, :controller

  def show(conn, %{"slug" => slug}) do
    case Kewkew.Queues.PublicLookup.fetch_queue(slug) do
      {:ok, nil} ->
        conn
        |> put_status(:not_found)
        |> render(:unavailable, page_title: "Queue unavailable")

      {:ok, %{queue: queue, session: session}} ->
        conn
        |> render(:show,
          page_title: queue.name,
          queue: queue,
          location: queue.location,
          service: queue.service,
          availability: availability(session)
        )

      {:error, _error} ->
        conn
        |> put_status(:not_found)
        |> render(:unavailable, page_title: "Queue unavailable")
    end
  end

  defp availability(%{status: :open}), do: %{label: "Open now", state: :open}
  defp availability(%{status: :paused}), do: %{label: "Temporarily paused", state: :paused}
  defp availability(_session), do: %{label: "Not accepting visitors", state: :closed}
end
