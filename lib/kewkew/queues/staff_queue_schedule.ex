defmodule Kewkew.Queues.StaffQueueSchedule do
  @moduledoc "Validates and persists recurring schedule configuration for a queue."

  alias Kewkew.Queues.QueueSchedule
  alias Kewkew.Repo

  @weekdays %{
    "1" => 1,
    "2" => 2,
    "3" => 3,
    "4" => 4,
    "5" => 5,
    "6" => 6,
    "7" => 7
  }

  @weekday_labels [
    {"Monday", "1"},
    {"Tuesday", "2"},
    {"Wednesday", "3"},
    {"Thursday", "4"},
    {"Friday", "5"},
    {"Saturday", "6"},
    {"Sunday", "7"}
  ]

  def weekday_labels, do: @weekday_labels

  def form_params(nil) do
    %{
      "schedule_enabled" => "false",
      "weekdays" => [],
      "signup_open_time" => "",
      "service_start_time" => "",
      "ticket_cap" => ""
    }
  end

  def form_params(schedule) do
    %{
      "schedule_enabled" => "true",
      "weekdays" => Enum.map(schedule.weekdays, &to_string/1),
      "signup_open_time" => Calendar.strftime(schedule.signup_open_time, "%H:%M"),
      "service_start_time" => Calendar.strftime(schedule.service_start_time, "%H:%M"),
      "ticket_cap" => if(schedule.ticket_cap, do: to_string(schedule.ticket_cap), else: "")
    }
  end

  def validate(params, timezone) when is_map(params) do
    if Map.get(params, "schedule_enabled") in ["true", true] do
      validate_enabled_schedule(params, timezone)
    else
      {:ok, :disabled}
    end
  end

  def validate(_params, _timezone),
    do: {:error, [{:schedule, "Enter valid recurring queue settings."}]}

  def save!(_queue_id, schedule, :disabled) do
    if schedule do
      Ash.destroy!(schedule,
        action: :delete,
        domain: Kewkew.Queues,
        authorize?: false
      )
    end

    nil
  end

  def save!(queue_id, nil, configuration) do
    Ash.create!(
      QueueSchedule,
      Map.put(configuration, :queue_id, queue_id),
      action: :create,
      domain: Kewkew.Queues,
      authorize?: false
    )
  end

  def save!(_queue_id, schedule, configuration) do
    Ash.update!(schedule, configuration,
      action: :update,
      domain: Kewkew.Queues,
      authorize?: false
    )
  end

  defp validate_enabled_schedule(params, timezone) do
    weekdays = parse_weekdays(Map.get(params, "weekdays"))
    signup_open_time = parse_time(Map.get(params, "signup_open_time"))
    service_start_time = parse_time(Map.get(params, "service_start_time"))
    ticket_cap = parse_ticket_cap(Map.get(params, "ticket_cap"))
    valid_timezone? = valid_timezone?(timezone)

    errors =
      []
      |> maybe_add_error(weekdays == :invalid, {:weekdays, "Choose at least one valid weekday."})
      |> maybe_add_error(
        signup_open_time == :invalid,
        {:signup_open_time, "Enter a valid signup-open time."}
      )
      |> maybe_add_error(
        service_start_time == :invalid,
        {:service_start_time, "Enter a valid service-start time."}
      )
      |> maybe_add_error(
        signup_open_time != :invalid and service_start_time != :invalid and
          Time.compare(service_start_time, signup_open_time) != :gt,
        {:service_start_time, "Service must start later than signup opens."}
      )
      |> maybe_add_error(
        ticket_cap == :invalid,
        {:ticket_cap, "Enter a positive whole-number cap or leave it blank."}
      )
      |> maybe_add_error(
        not valid_timezone?,
        {:schedule, "Set a valid IANA timezone for this location."}
      )

    case errors do
      [] ->
        {:ok,
         %{
           weekdays: weekdays,
           signup_open_time: signup_open_time,
           service_start_time: service_start_time,
           ticket_cap: ticket_cap
         }}

      errors ->
        {:error, errors}
    end
  end

  defp parse_weekdays(weekdays) when is_list(weekdays) do
    parsed = Enum.map(weekdays, &Map.get(@weekdays, &1))

    if parsed != [] and Enum.all?(parsed, &is_integer/1) and
         length(Enum.uniq(parsed)) == length(parsed) do
      Enum.sort(parsed)
    else
      :invalid
    end
  end

  defp parse_weekdays(_weekdays), do: :invalid

  defp parse_time(value) when is_binary(value) do
    case {Regex.match?(~r/^\d{2}:\d{2}$/, value), Time.from_iso8601(value <> ":00")} do
      {true, {:ok, time}} -> time
      _ -> :invalid
    end
  end

  defp parse_time(_value), do: :invalid

  defp parse_ticket_cap(value) when value in [nil, ""], do: nil

  defp parse_ticket_cap(value) when is_binary(value) do
    case Integer.parse(value) do
      {cap, ""} when cap > 0 -> cap
      _ -> :invalid
    end
  end

  defp parse_ticket_cap(_value), do: :invalid

  defp valid_timezone?(timezone) when is_binary(timezone) do
    case Repo.query("SELECT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name = $1)", [timezone]) do
      {:ok, %{rows: [[true]]}} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp valid_timezone?(_timezone), do: false

  defp maybe_add_error(errors, true, error), do: [error | errors]
  defp maybe_add_error(errors, false, _error), do: errors
end
