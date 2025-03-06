defmodule Drowzee.SleepChecker do
  require Logger

  def naptime?(sleep_time, wake_time, timezone) do
    now = DateTime.now!(timezone)
    today_date = DateTime.to_date(now)

    with {:ok, sleep_datetime} <- parse_time(sleep_time, today_date, timezone),
         {:ok, wake_datetime} <- parse_time(wake_time, today_date, timezone) do
      Logger.debug("Sleep time: #{format(sleep_datetime, "{h24}:{m}:{s}")}, Wake time: #{format(wake_datetime, "{h24}:{m}:{s}")}, Now: #{format(now)}")
      result = case DateTime.compare(sleep_datetime, wake_datetime) do
          :gt ->
            DateTime.compare(now, sleep_datetime) in [:eq, :gt] or DateTime.compare(now, wake_datetime) == :lt
          :lt ->
            DateTime.compare(now, sleep_datetime) in [:eq, :gt] and DateTime.compare(now, wake_datetime) == :lt
          :eq ->
            Logger.warning("Sleep time and wake time cannot be the same!")
            false
        end
      {:ok, result}
    else
      {:error, error} -> {:error, error}
    end
  end

  defp parse_time(time_str, date, timezone) do
    case Timex.parse(time_str, "%-I:%M%p", :strftime) do
      {:ok, time} ->
        datetime = DateTime.new!(date, Time.new!(time.hour, time.minute, 0), timezone)
        {:ok, datetime}
      {:error, error} ->
        {:error, error}
    end
  end

  defp format(datetime, format \\ "{YYYY}-{0M}-{0D} {h24}:{m}:{s}") do
    case Timex.format(datetime, format) do
      {:ok, formatted} ->
        formatted
      {:error, error} ->
        raise "Invalid format: #{inspect(error)}"
    end
  end
end
