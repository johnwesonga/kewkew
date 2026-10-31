defmodule KewkewWeb.StaffQueueStatsLive do
  @moduledoc "Queue statistics for an authorized staff member."

  use KewkewWeb, :live_view

  alias Kewkew.Business.StaffAccess
  alias Kewkew.Queues.{StaffBoard, StaffQueueStats}

  @impl true
  def mount(%{"queue_id" => queue_id}, _session, socket) do
    case load_stats(socket.assigns.current_user.id, queue_id, 30) do
      {:ok, stats} -> {:ok, assign_stats(socket, stats)}
      {:error, :not_found} -> {:ok, Phoenix.LiveView.redirect(socket, to: "/staff")}
      {:error, :unavailable} -> {:ok, assign_unavailable(socket, queue_id, 30)}
    end
  end

  @impl true
  def handle_event("select_period", %{"days" => days}, socket) do
    case Integer.parse(days) do
      {days, ""} ->
        case load_stats(socket.assigns.current_user.id, socket.assigns.queue.id, days) do
          {:ok, stats} -> {:noreply, assign_stats(socket, stats)}
          {:error, :not_found} -> {:noreply, Phoenix.LiveView.redirect(socket, to: "/staff")}
          {:error, :unavailable} -> {:noreply, assign(socket, stats_error?: true)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  defp load_stats(user_id, queue_id, days), do: StaffQueueStats.fetch(user_id, queue_id, days)

  defp assign_stats(socket, stats) do
    completed = Enum.filter(stats.points, &(&1.wait_count > 0))
    total_served = Enum.reduce(stats.points, 0, &(&1.served + &2))
    total_with_wait = Enum.reduce(stats.points, 0, &(&1.wait_count + &2))

    overall_average =
      case completed do
        [] ->
          nil

        points ->
          weighted_wait = Enum.reduce(points, 0, &(&1.average_wait_minutes * &1.wait_count + &2))
          weighted_wait / total_with_wait
      end

    socket
    |> assign(
      queue: stats.queue,
      organization: stats.organization,
      location: stats.location,
      service: stats.service,
      days: stats.days,
      points: stats.points,
      total_served: total_served,
      average_wait_minutes: overall_average,
      max_served: max(Enum.max(Enum.map(stats.points, & &1.served), fn -> 0 end), 1),
      stats_error?: false,
      can_setup?:
        StaffAccess.can_manage_organization?(
          socket.assigns.current_user.id,
          stats.organization.id
        )
    )
  end

  defp assign_unavailable(socket, queue_id, days) do
    case StaffBoard.fetch_queue(socket.assigns.current_user.id, queue_id) do
      {:ok, board} ->
        socket
        |> assign(
          queue: board.queue,
          organization: board.organization,
          location: board.location,
          service: board.service,
          days: days,
          points: [],
          total_served: 0,
          average_wait_minutes: nil,
          max_served: 1,
          stats_error?: true,
          can_setup?:
            StaffAccess.can_manage_organization?(
              socket.assigns.current_user.id,
              board.organization.id
            )
        )

      {:error, :not_found} ->
        Phoenix.LiveView.redirect(socket, to: "/staff")
    end
  end

  def format_wait(nil), do: "No completed services"

  def format_wait(minutes) do
    minutes = round(minutes)
    hours = div(minutes, 60)
    remaining_minutes = rem(minutes, 60)

    if hours > 0 do
      "#{hours}h #{remaining_minutes}m"
    else
      "#{remaining_minutes} min"
    end
  end

  def bar_height(served, max_served),
    do: max(round(served / max_served * 180), if(served > 0, do: 4, else: 0))

  def bar_x(index, count), do: index * (900 / count)
  def bar_width(count), do: max(2, 900 / count - 4)

  def date_label(date, days) when days <= 7, do: Calendar.strftime(date, "%a")
  def date_label(date, _days), do: Calendar.strftime(date, "%-m/%-d")
end
