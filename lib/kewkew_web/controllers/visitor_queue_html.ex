defmodule KewkewWeb.VisitorQueueHTML do
  @moduledoc "Public pages for visitors opening a queue link."

  use KewkewWeb, :html

  embed_templates "visitor_queue_html/*"

  def scheduled_service_time(schedule, timezone) do
    weekdays =
      schedule.weekdays
      |> Enum.map(&weekday_name/1)
      |> Enum.join(", ")

    time = Calendar.strftime(schedule.service_start_time, "%I:%M %p") |> String.trim_leading("0")

    "#{weekdays} at #{time} (#{timezone})"
  end

  def scheduled_service_time(_schedule, timezone, %{service_starts_at: starts_at}) do
    local = DateTime.shift_zone!(starts_at, timezone)
    "#{Calendar.strftime(local, "%A, %B %-d at %-I:%M %p")} (#{timezone})"
  end

  def scheduled_service_time(schedule, timezone, _signup_window),
    do: scheduled_service_time(schedule, timezone)

  def signup_countdown_copy(%{state: :open, seconds_until_close: seconds}) do
    minutes = max(div(seconds + 59, 60), 1)
    "You have #{minutes} #{if minutes == 1, do: "minute", else: "minutes"} to sign up."
  end

  def signup_countdown_copy(%{state: :upcoming, seconds_until_open: seconds}) do
    minutes = max(div(seconds + 59, 60), 1)
    "Signup opens in #{minutes} #{if minutes == 1, do: "minute", else: "minutes"}."
  end

  defp weekday_name(1), do: "Monday"
  defp weekday_name(2), do: "Tuesday"
  defp weekday_name(3), do: "Wednesday"
  defp weekday_name(4), do: "Thursday"
  defp weekday_name(5), do: "Friday"
  defp weekday_name(6), do: "Saturday"
  defp weekday_name(7), do: "Sunday"
  defp weekday_name(_day), do: "?"
end
