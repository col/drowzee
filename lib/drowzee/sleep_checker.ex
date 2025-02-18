defmodule Drowzee.SleepChecker do
  def naptime?(sleep_time, wake_time, timezone) do
    now = DateTime.now!(timezone)
    today_date = Date.utc_today()

    {:ok, sleep_datetime} = parse_time(sleep_time, today_date, timezone)
    {:ok, wake_datetime} = parse_time(wake_time, today_date, timezone)

    wake_datetime =
      if DateTime.compare(sleep_datetime, wake_datetime) == :gt do
        DateTime.add(wake_datetime, 86400, :second) # Move wake time to the next day
      else
        wake_datetime
      end

    DateTime.compare(now, sleep_datetime) in [:eq, :gt] and DateTime.compare(now, wake_datetime) == :lt
  end

  def parse_time(time_str, timezone) do
    today_date = Date.utc_today()
    parse_time(time_str, today_date, timezone)
  end

  defp parse_time(time_str, date, timezone) do
    case Timex.parse(time_str, "%I:%M%p", :strftime) do
      {:ok, time} ->
        datetime =
          DateTime.new!(date, Time.new!(time.hour, time.minute, 0), timezone)
        {:ok, datetime}

      error -> error
    end
  end
end
