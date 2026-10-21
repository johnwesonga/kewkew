defmodule KewkewWeb.VisitorQueueController do
  use KewkewWeb, :controller

  def show(conn, %{"slug" => slug}) do
    case Kewkew.Queues.PublicLookup.fetch_queue(slug) do
      {:ok, nil} ->
        conn
        |> put_status(:not_found)
        |> render(:unavailable, page_title: "Queue unavailable")

      {:ok, %{queue: queue, session: session, active_ticket_count: active_ticket_count}} ->
        current_availability =
          availability(session, active_ticket_count, queue.max_active_tickets)

        conn
        |> render(:show,
          page_title: queue.name,
          queue: queue,
          location: queue.location,
          service: queue.service,
          availability: current_availability
        )

      {:error, _error} ->
        conn
        |> put_status(:not_found)
        |> render(:unavailable, page_title: "Queue unavailable")
    end
  end

  def join(conn, %{"slug" => slug}) do
    case Kewkew.Queues.PublicLookup.fetch_queue(slug) do
      {:ok, %{queue: queue, session: session, active_ticket_count: active_ticket_count}} ->
        render_join(conn, queue, session, active_ticket_count, nil, nil)

      _ ->
        conn
        |> put_status(:not_found)
        |> render(:unavailable, page_title: "Queue unavailable")
    end
  end

  def create_join(conn, %{"slug" => slug, "join" => %{"attempt_token" => attempt_token}}) do
    case Kewkew.Queues.VisitorJoin.join_anonymous(slug, attempt_token) do
      {:ok, %{tracking_token: token}} ->
        redirect(conn, to: "/t/#{token}")

      {:error, reason} ->
        case Kewkew.Queues.PublicLookup.fetch_queue(slug) do
          {:ok, %{queue: queue, session: session, active_ticket_count: active_ticket_count}} ->
            message = join_error_message(reason)
            render_join(conn, queue, session, active_ticket_count, message, attempt_token)

          _ ->
            conn
            |> put_status(:not_found)
            |> render(:unavailable, page_title: "Queue unavailable")
        end
    end
  end

  def create_join(conn, %{"slug" => slug}) do
    case Kewkew.Queues.PublicLookup.fetch_queue(slug) do
      {:ok, %{queue: queue, session: session, active_ticket_count: active_ticket_count}} ->
        render_join(
          conn,
          queue,
          session,
          active_ticket_count,
          "Please try joining again.",
          nil
        )

      _ ->
        conn
        |> put_status(:not_found)
        |> render(:unavailable, page_title: "Queue unavailable")
    end
  end

  def track(conn, %{"token" => token}) do
    case Kewkew.Queues.PublicLookup.fetch_tracking_ticket(token) do
      {:ok, nil} ->
        conn
        |> put_status(:not_found)
        |> render(:unavailable, page_title: "Ticket unavailable")

      {:ok, ticket_data} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> put_resp_header("referrer-policy", "no-referrer")
        |> render(:ticket,
          page_title: "Ticket ##{ticket_data.ticket.ticket_number}",
          ticket: ticket_data.ticket,
          queue: ticket_data.queue,
          location: ticket_data.location,
          service: ticket_data.service
        )
    end
  end

  defp render_join(conn, queue, session, active_ticket_count, error_message, attempt_token) do
    availability = availability(session, active_ticket_count, queue.max_active_tickets)
    can_join? = availability.state == :open and queue.identity_policy == :anonymous
    attempt_token = attempt_token || random_attempt_token()

    message =
      cond do
        availability.state != :open ->
          availability.message

        queue.identity_policy != :anonymous ->
          "This queue requires a first and last name before you can join."

        true ->
          error_message
      end

    render(conn, :join,
      page_title: "Join #{queue.name}",
      queue: queue,
      location: queue.location,
      service: queue.service,
      availability: availability,
      can_join?: can_join?,
      message: message,
      form: Phoenix.Component.to_form(%{"attempt_token" => attempt_token}, as: :join)
    )
  end

  defp random_attempt_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp join_error_message(:full),
    do: "This queue has reached capacity. Please ask staff for help."

  defp join_error_message(:name_required),
    do: "This queue needs your name. Please use the name entry flow."

  defp join_error_message(:unavailable),
    do: "This queue is no longer accepting visitors. Please check its availability."

  defp join_error_message(_reason), do: "We could not add you to the queue. Please try again."

  def services(conn, %{"location_id" => location_id}) do
    case Kewkew.Queues.PublicLookup.list_location_queues(location_id) do
      {:ok, nil} ->
        conn
        |> put_status(:not_found)
        |> render(:unavailable, page_title: "Services unavailable")

      {:ok, %{location: location, queues: queues}} ->
        services =
          Enum.map(queues, fn %{queue: queue, session: session, active_ticket_count: count} ->
            %{
              queue: queue,
              service: queue.service,
              availability: availability(session, count, queue.max_active_tickets)
            }
          end)

        conn
        |> render(:services,
          page_title: "Choose a service",
          location: location,
          services: services
        )

      {:error, _error} ->
        conn
        |> put_status(:not_found)
        |> render(:unavailable, page_title: "Services unavailable")
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
