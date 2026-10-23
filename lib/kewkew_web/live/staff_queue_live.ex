defmodule KewkewWeb.StaffQueueLive do
  @moduledoc "Live board for monitoring one staff member's authorized queue."

  use KewkewWeb, :live_view

  alias Kewkew.Queues.{
    StaffBoard,
    StaffCallNext,
    StaffCancelTicket,
    StaffCompleteService,
    StaffOpenQueueSession,
    StaffRecallNoShow,
    StaffSkipVisitor,
    StaffStartServing,
    StaffUpdateQueueSessionStatus,
    Updates
  }

  @impl true
  def mount(%{"queue_id" => queue_id}, _session, socket) do
    user_id = socket.assigns.current_user.id

    case StaffBoard.fetch_queue(user_id, queue_id) do
      {:ok, board} ->
        if connected?(socket) do
          Updates.subscribe_queue(board.queue.id)
          if board.session, do: Updates.subscribe(board.session.id)
        end

        {:ok, assign_board(socket, board)}

      {:error, :not_found} ->
        {:ok, Phoenix.LiveView.redirect(socket, to: "/staff")}
    end
  end

  @impl true
  def handle_info({:queue_session_updated, session_id}, socket) do
    if socket.assigns.session && socket.assigns.session.id == session_id do
      refresh_board(socket)
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:queue_updated, queue_id}, socket) do
    if socket.assigns.queue.id == queue_id do
      refresh_board(socket)
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket), do: refresh_board(socket)

  @impl true
  def handle_event("open_session", _params, socket) do
    case StaffOpenQueueSession.open_session(
           socket.assigns.current_user.id,
           socket.assigns.queue.id
         ) do
      {:ok, _session} ->
        socket = assign_board_from_refresh(socket)
        {:noreply, Phoenix.LiveView.put_flash(socket, :info, "The queue session is open.")}

      {:error, :queue_inactive} ->
        {:noreply,
         Phoenix.LiveView.put_flash(
           socket,
           :error,
           "This queue is inactive. Reactivate it before opening a session."
         )}

      {:error, :location_inactive} ->
        {:noreply,
         Phoenix.LiveView.put_flash(
           socket,
           :error,
           "This location is inactive. Reactivate it before opening a session."
         )}

      {:error, :service_inactive} ->
        {:noreply,
         Phoenix.LiveView.put_flash(
           socket,
           :error,
           "This service is inactive. Reactivate it before opening a session."
         )}

      {:error, :session_already_open} ->
        socket = assign_board_from_refresh(socket)

        {:noreply,
         Phoenix.LiveView.put_flash(socket, :info, "A session is already open or paused.")}

      {:error, _reason} ->
        {:noreply,
         Phoenix.LiveView.put_flash(socket, :error, "Unable to open this queue session.")}
    end
  end

  @impl true
  def handle_event("pause_session", _params, socket) do
    transition_session(socket, :pause)
  end

  @impl true
  def handle_event("resume_session", _params, socket) do
    transition_session(socket, :resume)
  end

  @impl true
  def handle_event("call_next", _params, socket) do
    case StaffCallNext.call_next(socket.assigns.current_user.id, socket.assigns.queue.id) do
      {:ok, ticket} ->
        {:noreply,
         socket
         |> assign_board_from_refresh()
         |> Phoenix.LiveView.put_flash(:info, "Ticket ##{ticket.ticket_number} has been called.")}

      {:error, :no_waiting} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :info, "No visitors are waiting.")}

      {:error, :no_session} ->
        {:noreply,
         Phoenix.LiveView.put_flash(socket, :error, "This queue has no active session.")}

      {:error, _reason} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Unable to call the next visitor.")}
    end
  end

  @impl true
  def handle_event("start_serving", params, socket) do
    ticket_id = Map.get(params, "ticket_id") || Map.get(params, "ticket-id")

    case start_serving(socket, ticket_id) do
      {:ok, ticket} ->
        {:noreply,
         socket
         |> assign_board_from_refresh()
         |> Phoenix.LiveView.put_flash(
           :info,
           "Ticket ##{ticket.ticket_number} is now being served."
         )}

      {:error, :not_called} ->
        {:noreply,
         socket
         |> assign_board_from_refresh()
         |> Phoenix.LiveView.put_flash(:info, "That ticket is no longer waiting to be served.")}

      {:error, _reason} ->
        {:noreply,
         Phoenix.LiveView.put_flash(socket, :error, "Unable to start service for that ticket.")}
    end
  end

  @impl true
  def handle_event("complete_service", params, socket) do
    ticket_id = Map.get(params, "ticket_id") || Map.get(params, "ticket-id")

    case complete_service(socket, ticket_id) do
      {:ok, ticket} ->
        {:noreply,
         socket
         |> assign_board_from_refresh()
         |> Phoenix.LiveView.put_flash(
           :info,
           "Service for ticket ##{ticket.ticket_number} is complete."
         )}

      {:error, :not_serving} ->
        {:noreply,
         socket
         |> assign_board_from_refresh()
         |> Phoenix.LiveView.put_flash(:info, "That ticket is no longer being served.")}

      {:error, _reason} ->
        {:noreply,
         Phoenix.LiveView.put_flash(socket, :error, "Unable to complete service for that ticket.")}
    end
  end

  @impl true
  def handle_event("skip_visitor", params, socket) do
    ticket_id = Map.get(params, "ticket_id") || Map.get(params, "ticket-id")

    case skip_visitor(socket, ticket_id) do
      {:ok, ticket} ->
        {:noreply,
         socket
         |> assign_board_from_refresh()
         |> Phoenix.LiveView.put_flash(
           :info,
           "Ticket ##{ticket.ticket_number} was marked as a no-show."
         )}

      {:error, :not_called} ->
        {:noreply,
         socket
         |> assign_board_from_refresh()
         |> Phoenix.LiveView.put_flash(:info, "That ticket is no longer eligible to skip.")}

      {:error, _reason} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Unable to skip that visitor.")}
    end
  end

  @impl true
  def handle_event("recall_no_show", params, socket) do
    ticket_id = Map.get(params, "ticket_id") || Map.get(params, "ticket-id")

    case recall_no_show(socket, ticket_id) do
      {:ok, ticket} ->
        {:noreply,
         socket
         |> assign_board_from_refresh()
         |> Phoenix.LiveView.put_flash(
           :info,
           "Ticket ##{ticket.ticket_number} returned to the end of the line."
         )}

      {:error, :not_no_show} ->
        {:noreply,
         socket
         |> assign_board_from_refresh()
         |> Phoenix.LiveView.put_flash(:info, "That ticket is no longer eligible for recall.")}

      {:error, _reason} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Unable to requeue that visitor.")}
    end
  end

  @impl true
  def handle_event("cancel_ticket", params, socket) do
    ticket_id = Map.get(params, "ticket_id") || Map.get(params, "ticket-id")

    case cancel_ticket(socket, ticket_id) do
      {:ok, ticket} ->
        {:noreply,
         socket
         |> assign_board_from_refresh()
         |> Phoenix.LiveView.put_flash(:info, "Ticket ##{ticket.ticket_number} was cancelled.")}

      {:error, :not_cancellable} ->
        {:noreply,
         socket
         |> assign_board_from_refresh()
         |> Phoenix.LiveView.put_flash(:info, "That ticket can no longer be cancelled.")}

      {:error, _reason} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Unable to cancel that ticket.")}
    end
  end

  defp start_serving(_socket, nil), do: {:error, :missing_ticket_id}

  defp start_serving(socket, ticket_id) do
    StaffStartServing.start_serving(
      socket.assigns.current_user.id,
      socket.assigns.queue.id,
      ticket_id
    )
  end

  defp complete_service(_socket, nil), do: {:error, :missing_ticket_id}

  defp complete_service(socket, ticket_id) do
    StaffCompleteService.complete_service(
      socket.assigns.current_user.id,
      socket.assigns.queue.id,
      ticket_id
    )
  end

  defp skip_visitor(_socket, nil), do: {:error, :missing_ticket_id}

  defp skip_visitor(socket, ticket_id) do
    StaffSkipVisitor.skip_visitor(
      socket.assigns.current_user.id,
      socket.assigns.queue.id,
      ticket_id
    )
  end

  defp recall_no_show(_socket, nil), do: {:error, :missing_ticket_id}

  defp recall_no_show(socket, ticket_id) do
    StaffRecallNoShow.recall_no_show(
      socket.assigns.current_user.id,
      socket.assigns.queue.id,
      ticket_id
    )
  end

  defp cancel_ticket(_socket, nil), do: {:error, :missing_ticket_id}

  defp cancel_ticket(socket, ticket_id) do
    StaffCancelTicket.cancel_ticket(
      socket.assigns.current_user.id,
      socket.assigns.queue.id,
      ticket_id
    )
  end

  defp refresh_board(socket) do
    case StaffBoard.fetch_queue(socket.assigns.current_user.id, socket.assigns.queue.id) do
      {:ok, board} ->
        if (connected?(socket) and board.session) &&
             (is_nil(socket.assigns.session) or socket.assigns.session.id != board.session.id) do
          Updates.subscribe(board.session.id)
        end

        {:noreply, assign_board(socket, board)}

      {:error, :not_found} ->
        {:noreply, Phoenix.LiveView.redirect(socket, to: "/")}
    end
  end

  defp assign_board_from_refresh(socket) do
    case StaffBoard.fetch_queue(socket.assigns.current_user.id, socket.assigns.queue.id) do
      {:ok, board} -> assign_board(socket, board)
      {:error, :not_found} -> Phoenix.LiveView.redirect(socket, to: "/staff")
    end
  end

  defp transition_session(socket, :pause) do
    transition_session(socket, :pause, &StaffUpdateQueueSessionStatus.pause/2)
  end

  defp transition_session(socket, :resume) do
    transition_session(socket, :resume, &StaffUpdateQueueSessionStatus.resume/2)
  end

  defp transition_session(socket, operation, transition) do
    case transition.(socket.assigns.current_user.id, socket.assigns.queue.id) do
      {:ok, _session} ->
        socket = assign_board_from_refresh(socket)

        message =
          if operation == :pause, do: "Visitor joins are paused.", else: "Visitor joins are open."

        {:noreply, Phoenix.LiveView.put_flash(socket, :info, message)}

      {:error, :no_active_session} ->
        socket = assign_board_from_refresh(socket)

        {:noreply,
         Phoenix.LiveView.put_flash(
           socket,
           :error,
           "There is no open or paused session to update."
         )}

      {:error, :invalid_transition} ->
        socket = assign_board_from_refresh(socket)

        {:noreply,
         Phoenix.LiveView.put_flash(
           socket,
           :info,
           "The session changed before your action completed."
         )}

      {:error, _reason} ->
        {:noreply,
         Phoenix.LiveView.put_flash(socket, :error, "Unable to update this queue session.")}
    end
  end

  defp assign_board(socket, board) do
    tickets_by_status = Enum.group_by(board.tickets, & &1.status)

    socket
    |> assign(
      queue: board.queue,
      location: board.location,
      service: board.service,
      session: board.session,
      session_status: session_status(board.session),
      can_open_session?:
        (is_nil(board.session) or board.session.status == :closed) and board.queue.active? and
          board.location.active? and board.service.active?,
      session_can_be_opened?: is_nil(board.session) or board.session.status == :closed,
      session_open_block_reason: session_open_block_reason(board),
      show_names?: board.queue.identity_policy == :name_required,
      waiting_count: length(Map.get(tickets_by_status, :waiting, [])),
      called_count: length(Map.get(tickets_by_status, :called, [])),
      serving_count: length(Map.get(tickets_by_status, :serving, [])),
      no_show_count: length(board.no_show_tickets),
      active_count:
        length(Map.get(tickets_by_status, :waiting, [])) +
          length(Map.get(tickets_by_status, :called, [])) +
          length(Map.get(tickets_by_status, :serving, []))
    )
    |> stream(:tickets, board.tickets, reset: true)
    |> stream(:no_show_tickets, board.no_show_tickets, reset: true)
  end

  defp session_status(nil), do: "No queue session"
  defp session_status(%{status: :open}), do: "Open"
  defp session_status(%{status: :paused}), do: "Paused"
  defp session_status(%{status: :closed}), do: "Closed"

  defp session_status(_session), do: "Unavailable"

  defp session_open_block_reason(%{queue: %{active?: false}}),
    do: "This queue is inactive. Reactivate it before opening a session."

  defp session_open_block_reason(%{location: %{active?: false}}),
    do: "This location is inactive. Reactivate it before opening a session."

  defp session_open_block_reason(%{service: %{active?: false}}),
    do: "This service is inactive. Reactivate it before opening a session."

  defp session_open_block_reason(_board), do: nil

  defp session_status_class(%{status: :open}), do: "open"
  defp session_status_class(%{status: :paused}), do: "paused"
  defp session_status_class(%{status: :closed}), do: "closed"
  defp session_status_class(_session), do: "closed"

  defp person_initials(_ticket, false), do: "—"
  defp person_initials(%{first_name: nil}, true), do: "—"

  defp person_initials(ticket, true) do
    [ticket.first_name, ticket.last_name]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  defp ticket_status_class(:waiting), do: "waiting"
  defp ticket_status_class(:called), do: "called"
  defp ticket_status_class(:serving), do: "serving"
  defp ticket_status_class(:no_show), do: "no-show"

  defp ticket_status_label(:waiting), do: "Waiting"
  defp ticket_status_label(:called), do: "Called"
  defp ticket_status_label(:serving), do: "Being served"
  defp ticket_status_label(:no_show), do: "No-show"

  defp ticket_status_description(:waiting), do: "Waiting in line"
  defp ticket_status_description(:called), do: "Waiting to be seen"
  defp ticket_status_description(:serving), do: "Being helped by staff"
  defp ticket_status_description(:no_show), do: "Not present when called"
end
