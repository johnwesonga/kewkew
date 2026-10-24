defmodule KewkewWeb.StaffHTML do
  @moduledoc "Templates for staff pages."

  use KewkewWeb, :html

  embed_templates "staff_html/*"

  def queue_status(%{location: %{active?: false}}), do: {"Unavailable", "unavailable"}
  def queue_status(%{service: %{active?: false}}), do: {"Unavailable", "unavailable"}
  def queue_status(%{queue: %{active?: false}}), do: {"Inactive", "inactive"}
  def queue_status(%{session: nil}), do: {"No session", "no-session"}
  def queue_status(%{session: %{status: :open}}), do: {"Open", "open"}
  def queue_status(%{session: %{status: :paused}}), do: {"Paused", "paused"}
  def queue_status(%{session: %{status: :closed}}), do: {"Closed", "closed"}
  def queue_status(_queue), do: {"Unavailable", "unavailable"}

  def identity_policy_label(%{identity_policy: :name_required}), do: "First and last name"
  def identity_policy_label(_queue), do: "Anonymous"

  def capacity_label(%{max_active_tickets: nil}), do: "No limit"

  def capacity_label(%{max_active_tickets: capacity}),
    do: "#{capacity} active visitors"

  def queue_schedule_label(nil), do: "Manual sessions"

  def queue_schedule_label(schedule) do
    weekdays =
      schedule.weekdays
      |> Enum.map(&weekday_label/1)
      |> Enum.join(", ")

    signup_time = Calendar.strftime(schedule.signup_open_time, "%H:%M")
    service_time = Calendar.strftime(schedule.service_start_time, "%H:%M")

    "Recurring · #{weekdays} · Opens #{signup_time}, service #{service_time}"
  end

  defp weekday_label(1), do: "Mon"
  defp weekday_label(2), do: "Tue"
  defp weekday_label(3), do: "Wed"
  defp weekday_label(4), do: "Thu"
  defp weekday_label(5), do: "Fri"
  defp weekday_label(6), do: "Sat"
  defp weekday_label(7), do: "Sun"
  defp weekday_label(_day), do: "?"
end
