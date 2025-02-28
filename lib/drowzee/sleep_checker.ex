defmodule Drowzee.SleepChecker do
  require Logger

  def naptime?(sleep_time, wake_time, timezone) do
    now = DateTime.now!(timezone)
    today_date = DateTime.to_date(now)

    with {:ok, sleep_datetime} <- parse_time(sleep_time, today_date, timezone),
         {:ok, wake_datetime} <- parse_time(wake_time, today_date, timezone) do
      Logger.debug("Sleep time: #{inspect(sleep_datetime)}, Wake time: #{inspect(wake_datetime)}, Now: #{inspect(now)}")

      case DateTime.compare(sleep_datetime, wake_datetime) do
        :gt ->
          DateTime.compare(now, sleep_datetime) in [:eq, :gt] or DateTime.compare(now, wake_datetime) == :lt
        :lt ->
          DateTime.compare(now, sleep_datetime) in [:eq, :gt] and DateTime.compare(now, wake_datetime) == :lt
        :eq ->
          Logger.warning("Sleep time and wake time cannot be the same!")
          false
      end
    else
      {:error, error} ->
        Logger.error("Failed to parse time: #{inspect(error)}")
        false
    end
  end

  defp parse_time(time_str, date, timezone) do
    case Timex.parse(time_str, "%I:%M%p", :strftime) do
      {:ok, time} ->
        datetime = DateTime.new!(date, Time.new!(time.hour, time.minute, 0), timezone)
        {:ok, datetime}
      {:error, error} ->
        {:error, error}
    end
  end
end
