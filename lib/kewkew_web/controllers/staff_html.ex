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
end
