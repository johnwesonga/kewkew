defmodule Kewkew.Queues.StaffQueueScheduleTest do
  use Kewkew.DataCase

  alias Kewkew.Queues.StaffQueueSchedule

  test "accepts an optional positive signup duration up to 24 hours" do
    assert {:ok, %{signup_duration_minutes: 1}} =
             StaffQueueSchedule.validate(schedule_params("1"), "Etc/UTC")

    assert {:ok, %{signup_duration_minutes: 1440}} =
             StaffQueueSchedule.validate(schedule_params("1440"), "Etc/UTC")

    assert {:ok, %{signup_duration_minutes: nil}} =
             StaffQueueSchedule.validate(schedule_params(""), "Etc/UTC")
  end

  test "rejects a zero, oversized, or nonnumeric signup duration" do
    for duration <- ["0", "1441", "one hour"] do
      assert {:error, errors} =
               StaffQueueSchedule.validate(schedule_params(duration), "Etc/UTC")

      assert {:signup_duration_minutes,
              "Enter a duration from 1 to 1440 minutes or leave it blank."} in errors
    end
  end

  defp schedule_params(duration) do
    %{
      "schedule_enabled" => "true",
      "weekdays" => ["1", "2"],
      "signup_open_time" => "09:00",
      "signup_duration_minutes" => duration,
      "service_start_time" => "10:00",
      "ticket_cap" => ""
    }
  end
end
