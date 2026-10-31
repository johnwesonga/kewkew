defmodule Kewkew.Queues.StaffQueueStats do
  @moduledoc "Loads daily service statistics for a queue after checking staff access."

  import Ecto.Query

  alias Kewkew.Business.StaffAccess
  alias Kewkew.Queues.{QueueSession, Ticket}
  alias Kewkew.Repo

  @periods [7, 30, 90]

  def periods, do: @periods

  def fetch(user_id, queue_id, days) when days in @periods do
    case StaffAccess.queue_for_user(user_id, queue_id) do
      nil ->
        {:error, :not_found}

      %{queue: queue} = context ->
        today = Date.utc_today()
        first_day = Date.add(today, -(days - 1))
        start_at = DateTime.new!(first_day, ~T[00:00:00], "Etc/UTC")
        end_at = DateTime.new!(Date.add(today, 1), ~T[00:00:00], "Etc/UTC")

        session_ids =
          from(session in QueueSession,
            where: session.queue_id == ^queue.id,
            select: session.id
          )

        completed =
          Repo.all(
            from ticket in Ticket,
              where:
                ticket.queue_session_id in subquery(session_ids) and
                  ticket.status == :completed and ticket.completed_at >= ^start_at and
                  ticket.completed_at < ^end_at,
              select: {ticket.completed_at, ticket.joined_at, ticket.started_at}
          )

        {:ok,
         Map.merge(context, %{
           first_day: first_day,
           last_day: today,
           days: days,
           points: build_points(first_day, days, completed)
         })}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  def fetch(_user_id, _queue_id, _days), do: {:error, :invalid_period}

  defp build_points(first_day, days, tickets) do
    grouped =
      Enum.group_by(tickets, fn {completed_at, _, _} -> DateTime.to_date(completed_at) end)

    for offset <- 0..(days - 1) do
      date = Date.add(first_day, offset)
      day_tickets = Map.get(grouped, date, [])
      wait_seconds = day_tickets |> Enum.map(&wait_seconds/1) |> Enum.reject(&is_nil/1)

      %{
        date: date,
        served: length(day_tickets),
        wait_count: length(wait_seconds),
        average_wait_minutes:
          case wait_seconds do
            [] -> nil
            seconds -> Enum.sum(seconds) / length(seconds) / 60
          end
      }
    end
  end

  defp wait_seconds({_completed_at, %DateTime{} = joined_at, %DateTime{} = started_at}) do
    DateTime.diff(started_at, joined_at, :second)
  end

  defp wait_seconds(_ticket), do: nil
end
