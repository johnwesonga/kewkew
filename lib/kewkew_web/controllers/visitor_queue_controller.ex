defmodule KewkewWeb.VisitorQueueController do
  @moduledoc "Public controller actions for visitor queue discovery, joining, and ticket tracking."

  use KewkewWeb, :controller

  @doc "Displays a public queue's details and current visitor availability."
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

  @doc "Returns the current public availability state so queue pages can refresh on changes."
  def availability_status(conn, %{"slug" => slug}) do
    response =
      case Kewkew.Queues.PublicLookup.fetch_queue(slug) do
        {:ok, %{session: session, active_ticket_count: active_ticket_count, queue: queue}} ->
          current_availability =
            availability(session, active_ticket_count, queue.max_active_tickets)

          %{state: Atom.to_string(current_availability.state)}

        _ ->
          %{state: "unavailable"}
      end

    conn
    |> put_resp_header("cache-control", "no-store")
    |> json(response)
  end

  @doc "Displays the queue's join form based on its configured identity policy."
  def join(conn, %{"slug" => slug}) do
    case Kewkew.Queues.PublicLookup.fetch_queue(slug) do
      {:ok, %{queue: queue, session: session, active_ticket_count: active_ticket_count}} ->
        render_join(conn, queue, session, active_ticket_count, nil, %{})

      _ ->
        conn
        |> put_status(:not_found)
        |> render(:unavailable, page_title: "Queue unavailable")
    end
  end

  @doc "Handles a visitor join submission according to the queue's persisted identity policy."
  def create_join(conn, %{"slug" => slug, "join" => params}) when is_map(params) do
    attempt_token = Map.get(params, "attempt_token")

    case Kewkew.Queues.VisitorJoin.join_visitor(slug, attempt_token, params) do
      {:ok, %{tracking_token: token}} ->
        redirect(conn, to: "/t/#{token}")

      {:error, reason} ->
        case Kewkew.Queues.PublicLookup.fetch_queue(slug) do
          {:ok, %{queue: queue, session: session, active_ticket_count: active_ticket_count}} ->
            render_join(conn, queue, session, active_ticket_count, reason, params)

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
          :invalid_attempt,
          %{}
        )

      _ ->
        conn
        |> put_status(:not_found)
        |> render(:unavailable, page_title: "Queue unavailable")
    end
  end

  @doc "Displays the private ticket page authorized by its tracking token."
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
          service: ticket_data.service,
          position: ticket_data.position,
          status_label: ticket_status_label(ticket_data.ticket.status),
          tracking_token: token,
          tracking_url: request_url(conn, "/t/#{token}"),
          csrf_token: Plug.CSRFProtection.get_csrf_token()
        )
    end
  end

  @doc "Cancels a waiting ticket using the visitor's private tracking token."
  def cancel_ticket(conn, %{"token" => token}) do
    case Kewkew.Queues.VisitorCancellation.cancel_by_tracking_token(token) do
      {:ok, _result} ->
        redirect(conn, to: "/t/#{token}")

      {:error, :not_allowed} ->
        conn
        |> redirect(to: "/t/#{token}")

      {:error, _reason} ->
        conn
        |> put_status(:not_found)
        |> render(:unavailable, page_title: "Ticket unavailable")
    end
  end

  @doc "Returns only the authorized visitor's current ticket status and position for polling."
  def track_status(conn, %{"token" => token}) do
    case Kewkew.Queues.PublicLookup.fetch_tracking_ticket(token) do
      {:ok, nil} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> put_resp_header("referrer-policy", "no-referrer")
        |> put_status(:not_found)
        |> json(%{error: "unavailable"})

      {:ok, ticket_data} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> put_resp_header("referrer-policy", "no-referrer")
        |> json(%{
          status: Atom.to_string(ticket_data.ticket.status),
          status_label: ticket_status_label(ticket_data.ticket.status),
          position: ticket_data.position
        })
    end
  end

  defp render_join(conn, queue, session, active_ticket_count, error_reason, params) do
    availability = availability(session, active_ticket_count, queue.max_active_tickets)
    can_join? = availability.state == :open

    attempt_token =
      if error_reason == :invalid_attempt,
        do: nil,
        else: Map.get(params, "attempt_token")

    attempt_token = attempt_token || random_attempt_token()

    message =
      cond do
        availability.state != :open ->
          availability.message

        true ->
          error_message(error_reason)
      end

    form_params = %{
      "attempt_token" => attempt_token,
      "first_name" => Map.get(params, "first_name", ""),
      "last_name" => Map.get(params, "last_name", "")
    }

    render(conn, :join,
      page_title: "Join #{queue.name}",
      queue: queue,
      location: queue.location,
      service: queue.service,
      availability: availability,
      can_join?: can_join?,
      message: message,
      field_errors: %{
        first_name: field_error(error_reason, :first_name),
        last_name: field_error(error_reason, :last_name)
      },
      form: Phoenix.Component.to_form(form_params, as: :join)
    )
  end

  defp random_attempt_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp error_message(:full),
    do: "This queue has reached capacity. Please ask staff for help."

  defp error_message(:invalid_attempt), do: "Please try joining again."

  defp error_message(:unavailable),
    do: "This queue is no longer accepting visitors. Please check its availability."

  defp error_message(:first_name_required), do: nil
  defp error_message(:last_name_required), do: nil
  defp error_message(:first_name_too_long), do: nil
  defp error_message(:last_name_too_long), do: nil
  defp error_message(nil), do: nil
  defp error_message(_reason), do: "We could not add you to the queue. Please try again."

  defp ticket_status_label(:waiting), do: "Waiting"
  defp ticket_status_label(:called), do: "Your number has been called"
  defp ticket_status_label(:serving), do: "Being served"
  defp ticket_status_label(:completed), do: "Service complete"
  defp ticket_status_label(:cancelled), do: "You left this queue"
  defp ticket_status_label(:no_show), do: "Marked as not present"

  defp field_error(:first_name_required, :first_name), do: "Enter your first name."
  defp field_error(:last_name_required, :last_name), do: "Enter your last name."
  defp field_error(:first_name_too_long, :first_name), do: "Use 100 characters or fewer."
  defp field_error(:last_name_too_long, :last_name), do: "Use 100 characters or fewer."
  defp field_error(_reason, _field), do: nil

  @doc "Lists the visitor-facing services and their availability for a location."
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

  defp request_url(conn, path) do
    uri = URI.parse(Plug.Conn.request_url(conn))
    URI.to_string(%{uri | path: path, query: nil, fragment: nil})
  end
end
