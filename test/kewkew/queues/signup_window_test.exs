defmodule Kewkew.Queues.SignupWindowTest do
  use Kewkew.DataCase

  alias Kewkew.Queues.SignupWindow

  @monday ~U[2026-11-02 15:00:00Z]

  test "returns the remaining duration while signup is open" do
    schedule = schedule(~T[14:50:00], 30)

    assert %{
             state: :open,
             seconds_until_close: 1200,
             opens_at: opens_at,
             closes_at: closes_at,
             service_starts_at: service_starts_at
           } =
             SignupWindow.current_or_next(schedule, "Etc/UTC", @monday)

    assert DateTime.compare(opens_at, ~U[2026-11-02 14:50:00Z]) == :eq
    assert DateTime.compare(closes_at, ~U[2026-11-02 15:20:00Z]) == :eq
    assert DateTime.compare(service_starts_at, ~U[2026-11-02 16:00:00Z]) == :eq
    assert SignupWindow.joinable?(%{state: :open})
  end

  test "returns the next opening before signup begins" do
    schedule = schedule(~T[15:05:00], 20)

    assert %{state: :upcoming, seconds_until_open: 300, opens_at: opens_at} =
             SignupWindow.current_or_next(schedule, "Etc/UTC", @monday)

    assert DateTime.compare(opens_at, ~U[2026-11-02 15:05:00Z]) == :eq
    refute SignupWindow.joinable?(%{state: :upcoming})
  end

  test "marks today's occurrence closed after its duration and points to the next one" do
    schedule = schedule(~T[14:00:00], 30)
    after_close = ~U[2026-11-02 14:30:00Z]

    assert %{state: :closed, opens_at: next_opening} =
             SignupWindow.current_or_next(schedule, "Etc/UTC", after_close)

    assert DateTime.compare(next_opening, ~U[2026-11-09 14:00:00Z]) == :eq
    refute SignupWindow.joinable?(%{state: :closed})
  end

  test "calculates recurring opening times in the queue location timezone" do
    schedule = schedule(~T[09:00:00], 45)
    before_local_open = ~U[2026-11-02 16:59:00Z]
    during_local_window = ~U[2026-11-02 17:10:00Z]

    assert %{state: :upcoming, opens_at: opening} =
             SignupWindow.current_or_next(schedule, "America/Los_Angeles", before_local_open)

    assert DateTime.compare(opening, ~U[2026-11-02 17:00:00Z]) == :eq

    assert %{state: :open, closes_at: closing} =
             SignupWindow.current_or_next(schedule, "America/Los_Angeles", during_local_window)

    assert DateTime.compare(closing, ~U[2026-11-02 17:45:00Z]) == :eq
  end

  test "keeps queues without a duration unlimited" do
    schedule = schedule(~T[14:50:00], nil)

    assert %{state: :open, closes_at: nil} =
             SignupWindow.current_or_next(schedule, "Etc/UTC", @monday)

    assert SignupWindow.joinable?(nil)
  end

  defp schedule(signup_open_time, duration_minutes) do
    %{
      weekdays: [1],
      signup_open_time: signup_open_time,
      signup_duration_minutes: duration_minutes,
      service_start_time: Time.add(signup_open_time, 70 * 60, :second)
    }
  end
end
