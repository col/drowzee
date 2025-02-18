defmodule Drowzee.Controller.SleepScheduleControllerTest do
  @moduledoc false
  use ExUnit.Case, async: false
  use Bonny.Axn.Test

  alias Drowzee.Controller.SleepScheduleController

  test "add is handled and returns axn" do
    axn = axn(:add)
    result = SleepScheduleController.call(axn, [])
    assert is_struct(result, Bonny.Axn)
  end

  test "modify is handled and returns axn" do
    axn = axn(:modify)
    result = SleepScheduleController.call(axn, [])
    assert is_struct(result, Bonny.Axn)
  end

  test "reconcile is handled and returns axn" do
    axn = axn(:reconcile)
    result = SleepScheduleController.call(axn, [])
    assert is_struct(result, Bonny.Axn)
  end

  test "delete is handled and returns axn" do
    axn = axn(:delete)
    result = SleepScheduleController.call(axn, [])
    assert is_struct(result, Bonny.Axn)
  end
end
