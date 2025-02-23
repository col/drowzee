defmodule Drowzee.K8s.SleepSchedule do
  def get_condition(sleep_schedule, type) do
    (sleep_schedule["status"]["conditions"] || [])
    |> Enum.filter(&(&1["type"] == type))
    |> List.first()
  end

  def put_condition(sleep_schedule, type, status, reason \\ nil, message \\ nil) do
    new_conditions = sleep_schedule["status"]["conditions"]
      |> Enum.filter(&(&1["type"] != type))
      |> List.insert_at(-1, Drowzee.K8s.Condition.new(type, status, reason, message))
    put_in(sleep_schedule, ["status", "conditions"], new_conditions)
  end
end
