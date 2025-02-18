defmodule Drowzee.Controller.SleepScheduleController do
  @moduledoc """
  Drowzee: SleepScheduleController controller.

  """
  use Bonny.ControllerV2

  step Bonny.Pluggable.SkipObservedGenerations
  step :handle_event

  # apply the resource
  def handle_event(%Bonny.Axn{action: action} = axn, _opts)
      when action in [:add, :modify, :reconcile] do
    # IO.puts("Apply: #{inspect(axn.resource)}")

    sleep_time = axn.resource["spec"]["sleepTime"]
    wake_time = axn.resource["spec"]["wakeTime"]
    timezone = axn.resource["spec"]["timezone"]

    IO.puts("Now: #{DateTime.now!(timezone)}")
    IO.puts("Sleep Time: #{inspect(Drowzee.SleepChecker.parse_time(sleep_time, timezone))}")
    IO.puts("Wake Time: #{inspect(Drowzee.SleepChecker.parse_time(wake_time, timezone))}")
    IO.puts("Timezone: #{timezone}")
    IO.puts("Naptime? = #{Drowzee.SleepChecker.naptime?(sleep_time, wake_time, timezone)}")

    case get_ingress(axn) do
      {:ok, ingress} ->
        IO.puts("Ingress: #{inspect(ingress)}")
      {:error, error} ->
        IO.puts("Error: #{inspect(error)}")
    end

    axn
    |> set_condition("naptime", Drowzee.SleepChecker.naptime?(sleep_time, wake_time, timezone), "Time for a nap?")
    |> success_event()
  end

  # delete the resource
  def handle_event(%Bonny.Axn{action: :delete} = axn, _opts) do
    IO.inspect(axn.resource)
    axn
  end

  defp get_ingress(%Bonny.Axn{resource: resource, conn: conn}) do
    IO.puts("Getting ingress #{resource["spec"]["ingressName"]}, namespace: #{resource["metadata"]["namespace"]}")
    operation = K8s.Client.get("networking.k8s.io/v1", :ingress, name: resource["spec"]["ingressName"], namespace: resource["metadata"]["namespace"])
    K8s.Client.run(conn, operation)
  end
end
