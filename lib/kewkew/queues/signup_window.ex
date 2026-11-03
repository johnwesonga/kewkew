defmodule Kewkew.Queues.SignupWindow do
  @moduledoc "Calculates the current or next recurring signup window using PostgreSQL timezone data."

  alias Kewkew.Repo

  @occurrence_sql """
  WITH local_today AS (
    SELECT timezone($3, $1::timestamptz)::date AS day
  ), occurrences AS (
    SELECT
      (local_today.day + day_offsets.day_offset + $2::time) AT TIME ZONE $3 AS opens_at,
      (local_today.day + day_offsets.day_offset)::date AS local_date,
      local_today.day AS today
    FROM local_today
    CROSS JOIN generate_series(-1, 7) AS day_offsets(day_offset)
    WHERE
      EXTRACT(ISODOW FROM local_today.day + day_offsets.day_offset)::integer =
        ANY($4::integer[])
  )
  SELECT opens_at, local_date, today,
    (local_date + $5::time) AT TIME ZONE $3 AS service_starts_at
  FROM occurrences ORDER BY opens_at
  """

  @doc "Returns the current or next recurring signup window, or nil without a schedule."
  def current_or_next(nil, _timezone, _now), do: nil

  def current_or_next(schedule, timezone, %DateTime{} = now) do
    duration = schedule.signup_duration_minutes

    case Repo.query(@occurrence_sql, [
           now,
           schedule.signup_open_time,
           timezone,
           schedule.weekdays,
           schedule.service_start_time
         ]) do
      {:ok, %{rows: rows}} ->
        case rows do
          [[_opens_at, _local_date, local_today, _service_starts_at] | _] ->
            find_window(rows, local_today, now, duration)

          [] ->
            %{state: :unavailable}
        end

      {:error, _reason} ->
        %{state: :unavailable}
    end
  end

  def current_or_next(schedule, timezone),
    do: current_or_next(schedule, timezone, DateTime.utc_now())

  def joinable?(nil), do: true
  def joinable?(%{state: :open}), do: true
  def joinable?(_window), do: false

  defp find_window(rows, local_today, now, duration) do
    occurrences =
      Enum.map(rows, fn [opens_at, local_date, _today, service_starts_at] ->
        {opens_at, local_date, service_starts_at}
      end)

    active =
      Enum.find(occurrences, fn {opens_at, _local_date, _service_starts_at} ->
        closes_at = if duration, do: DateTime.add(opens_at, duration * 60, :second)

        DateTime.compare(now, opens_at) != :lt and
          (is_nil(closes_at) or DateTime.compare(now, closes_at) == :lt)
      end)

    case active do
      {opens_at, _local_date, service_starts_at} ->
        build_window(:open, opens_at, service_starts_at, duration, now)

      nil ->
        next_or_closed(occurrences, local_today, duration, now)
    end
  end

  defp next_or_closed(occurrences, local_today, duration, now) do
    next =
      Enum.find(occurrences, fn {opens_at, _, _} -> DateTime.compare(opens_at, now) == :gt end)

    opens_later_today? =
      Enum.any?(occurrences, fn {opens_at, date, _service_starts_at} ->
        date == local_today and DateTime.compare(opens_at, now) == :gt
      end)

    state = if opens_later_today?, do: :upcoming, else: :closed

    case next do
      {opens_at, _local_date, service_starts_at} ->
        build_window(state, opens_at, service_starts_at, duration, now)

      nil ->
        nil
    end
  end

  defp build_window(state, opens_at, service_starts_at, duration, now) do
    closes_at = if duration, do: DateTime.add(opens_at, duration * 60, :second)

    %{
      state: state,
      opens_at: opens_at,
      service_starts_at: service_starts_at,
      closes_at: closes_at,
      seconds_until_open: max(DateTime.diff(opens_at, now, :second), 0),
      seconds_until_close: if(closes_at, do: max(DateTime.diff(closes_at, now, :second), 0))
    }
  end
end
