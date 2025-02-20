defmodule Drowzee.API.V1Beta1.SleepSchedule do
  @moduledoc """
  Drowzee: SleepSchedule CRD V1Beta1 version.

  Modify the `manifest/0` function in order to override the defaults,
  e.g. to define an openAPIV3 schema, add subresources or additional
  printer columns:

  ```
  def manifest() do
    struct!(
      defaults(),
      name: "v1beta1",
      schema: %{
        openAPIV3Schema: %{
          type: :object,
          properties: %{
            spec: %{
              type: :object,
              properties: %{
                foos: %{type: :integer}
              }
            },
            status: %{
              ...
            }
          }
        }
      },
      additionalPrinterColumns: [
        %{name: "foos", type: :integer, description: "Number of foos", jsonPath: ".spec.foos"}
      ],
      subresources: %{
        status: %{}
      }
    )
  end
  ```
  """
  use Bonny.API.Version,
    hub: true

  def manifest() do
    defaults()
    |> struct!(
      name: "v1beta1",
      schema: %{
        openAPIV3Schema: %{
          type: :object,
          properties: %{
            spec: %{
              type: :object,
              properties: %{
                deployments: %{
                  description: "The deployments that will be slept/woken.",
                  type: :array,
                  items: %{
                    type: :object,
                    properties: %{
                      name: %{
                        type: :string
                      }
                    },
                    required: [:name]
                  }
                },
                sleepTime: %{
                  description: "The time that the deployment will start sleeping(format: HH:MMam/pm)",
                  type: :string
                },
                wakeTime: %{
                  description: "The time that the deployment will wake up (format: HH:MMam/pm)",
                  type: :string
                },
                timezone: %{
                  description: "The timezone that the input times are based in",
                  type: :string
                },
                ingressName: %{
                  description: "The ingress that will be slept/woken.",
                  type: :string
                }
              },
              required: [:sleepTime, :timezone, :wakeTime, :deployments]
            }
          }
        }
      },
      additionalPrinterColumns: [
        %{name: "sleepTime", type: :string, description: "Starts Sleeping", jsonPath: ".spec.sleepTime"},
        %{name: "wakeTime", type: :string, description: "Wakes Up", jsonPath: ".spec.wakeTime"},
        %{name: "timezone", type: :string, description: "Timezone", jsonPath: ".spec.timezone"},
        %{name: "deployments", type: :string, description: "Deployments", jsonPath: ".spec.deployments[*].name"},
        %{name: "naptime?", type: :string, description: "Time for a nap?", jsonPath: ".status.conditions[?(@.type == \"naptime\")].status"},
        %{name: "ingressBackup?", type: :string, description: "Ingress Backup", jsonPath: ".status.conditions[?(@.type == \"ingressBackup\")].status"},
      ]
    )
    |> add_observed_generation_status()
    |> add_conditions()
  end
end
