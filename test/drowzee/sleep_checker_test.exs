defmodule Drowzee.SleepCheckerTest do
  @moduledoc false
  use ExUnit.Case, async: false

  test "parses a valid time" do
    assert {:ok, %DateTime{}} = Drowzee.SleepChecker.parse_time("12:00am", "Australia/Sydney")
    assert {:ok, %DateTime{}} = Drowzee.SleepChecker.parse_time("10:45am", "Australia/Sydney")
    assert {:ok, %DateTime{}} = Drowzee.SleepChecker.parse_time("02:30pm", "Australia/Sydney")
  end

  test "fails to parse an invalid time" do
    assert {:error, "Expected `hour between 1 and 12` at line 1, column 1."} = Drowzee.SleepChecker.parse_time("00:01am", "Australia/Sydney")
    assert {:error, "Expected `hour between 1 and 12` at line 1, column 1."} = Drowzee.SleepChecker.parse_time("2:01am", "Australia/Sydney")
    assert {:error, "Expected `hour between 1 and 12` at line 1, column 1."} = Drowzee.SleepChecker.parse_time("13:00am", "Australia/Sydney")
    assert {:error, "Expected `minute` at line 1, column 4."} = Drowzee.SleepChecker.parse_time("12:65am", "Australia/Sydney")
  end

  test "returns true when it's naptime" do
    # Very lazy way to write this test
    assert Drowzee.SleepChecker.naptime?("12:00am", "11:59pm", "Australia/Sydney")
  end

  test "returns false when it's not naptime" do
    # Very lazy way to write this test
    assert !Drowzee.SleepChecker.naptime?("11:58pm", "11:59pm", "Australia/Sydney")
  end
end
