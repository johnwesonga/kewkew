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

  defp weekday_name(1), do: "Monday"
  defp weekday_name(2), do: "Tuesday"
  defp weekday_name(3), do: "Wednesday"
  defp weekday_name(4), do: "Thursday"
  defp weekday_name(5), do: "Friday"
  defp weekday_name(6), do: "Saturday"
  defp weekday_name(7), do: "Sunday"
  defp weekday_name(_day), do: "?"
end
