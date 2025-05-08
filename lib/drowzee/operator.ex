defmodule Drowzee.Operator do
  @moduledoc """
  Defines the operator.

  The operator resource defines custom resources, watch queries and their
  controllers and serves as the entry point to the watching and handling
  processes.
  """

  use Bonny.Operator, default_watch_namespace: "default"

  step(Bonny.Pluggable.Logger, level: :debug)
  step(:delegate_to_controller)
  step(Bonny.Pluggable.ApplyStatus)
  step(Bonny.Pluggable.ApplyDescendants)

  require Logger

  @impl Bonny.Operator
  def controllers(_wrong_namespace, _opts) do
    namespaces = Drowzee.Config.namespaces()
    # Note: To watch all namespaces set BONNY_POD_NAMESPACE to "__ALL__"
    Logger.info("Configuring SleepScheduleController controller with namespace(s): #{Enum.join(namespaces, ", ")}")
    
    if Enum.member?(namespaces, "__ALL__") do
      # Watch all namespaces
      [
        %{
          query: K8s.Client.watch("drowzee.challengr.io/v1beta1", "SleepSchedule", namespace: :all),
          controller: Drowzee.Controller.SleepScheduleController
        }
      ]
    else
      # Watch specific namespaces
      Enum.map(namespaces, fn namespace ->
        %{
          query: K8s.Client.watch("drowzee.challengr.io/v1beta1", "SleepSchedule", namespace: namespace),
          controller: Drowzee.Controller.SleepScheduleController
        }
      end)
    end
  end

  @impl Bonny.Operator
  def crds() do
    [
      %Bonny.API.CRD{
        names: %{
          kind: "SleepSchedule",
          singular: "sleepschedule",
          plural: "sleepschedules",
          shortNames: ["ss"]
        },
        group: "drowzee.challengr.io",
        versions: [Drowzee.API.V1Beta1.SleepSchedule],
        scope: :Namespaced
      }
    ]
  end
end
