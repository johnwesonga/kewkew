defmodule KewkewWeb.StaffQueueLive do
  @moduledoc "Live board for monitoring one staff member's authorized queue."

  use KewkewWeb, :live_view

  alias Kewkew.Queues.{StaffBoard, Updates}

  @impl true
  def mount(%{"queue_id" => queue_id}, _session, socket) do
    user_id = socket.assigns.current_user.id

    case StaffBoard.fetch_queue(user_id, queue_id) do
      {:ok, board} ->
        if connected?(socket) and board.session do
          Updates.subscribe(board.session.id)
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
  def handle_event("refresh", _params, socket), do: refresh_board(socket)

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

  defp assign_board(socket, board) do
    tickets_by_status = Enum.group_by(board.tickets, & &1.status)

    socket
    |> assign(
      queue: board.queue,
      location: board.location,
      service: board.service,
      session: board.session,
      session_status: session_status(board.session),
      show_names?: board.queue.identity_policy == :name_required,
      waiting_count: length(Map.get(tickets_by_status, :waiting, [])),
      called_count: length(Map.get(tickets_by_status, :called, [])),
      serving_count: length(Map.get(tickets_by_status, :serving, [])),
      active_count: length(board.tickets)
    )
    |> stream(:waiting_tickets, Map.get(tickets_by_status, :waiting, []), reset: true)
    |> stream(:called_tickets, Map.get(tickets_by_status, :called, []), reset: true)
    |> stream(:serving_tickets, Map.get(tickets_by_status, :serving, []), reset: true)
  end

  defp session_status(nil), do: "No queue session"
  defp session_status(%{status: :open}), do: "Open"
  defp session_status(%{status: :paused}), do: "Paused"
  defp session_status(%{status: :closed}), do: "Closed"

  defp session_status(_session), do: "Unavailable"

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
end
