defmodule Drowzee.Operator do
  @moduledoc """
  Defines the operator.

  The operator resource defines custom resources, watch queries and their
  controllers and serves as the entry point to the watching and handling
  processes.
  """

  use Bonny.Operator, default_watch_namespace: "default"

  step(Bonny.Pluggable.Logger, level: :info)
  step(:delegate_to_controller)
  step(Bonny.Pluggable.ApplyStatus)
  step(Bonny.Pluggable.ApplyDescendants)

  @impl Bonny.Operator
  def controllers(watching_namespace, _opts) do
    [
      %{
        query:
          K8s.Client.watch("drowzee.challengr.io/v1beta1", "SleepSchedule",
            namespace: watching_namespace
          ),
        controller: Drowzee.Controller.SleepScheduleController
      }
    ]
  end

  @impl Bonny.Operator
  def crds() do
    [
      %Bonny.API.CRD{
        names: %{
          kind: "SleepSchedule",
          singular: "sleepschedule",
          plural: "sleepschedules",
          shortNames: []
        },
        group: "drowzee.challengr.io",
        versions: [Drowzee.API.V1Beta1.SleepSchedule],
        scope: :Namespaced
      }
    ]
  end
end
