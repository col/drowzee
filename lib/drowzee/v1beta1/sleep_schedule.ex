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
                enabled: %{
                  type: :boolean,
                  description: "Whether this schedule is enabled.",
                  default: true
                },
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
        %{name: "Enabled", type: :string, description: "Enabled", jsonPath: ".spec.enabled"},
        %{name: "SleepTime", type: :string, description: "Starts Sleeping", jsonPath: ".spec.sleepTime"},
        %{name: "WakeTime", type: :string, description: "Wakes Up", jsonPath: ".spec.wakeTime"},
        %{name: "Timezone", type: :string, description: "Timezone", jsonPath: ".spec.timezone"},
        %{name: "Deployments", type: :string, description: "Deployments", jsonPath: ".spec.deployments[*].name"},
        %{name: "Statefulsets", type: :string, description: "Statefulsets", jsonPath: ".spec.statefulsets[*].name"},
        %{name: "Cronjobs", type: :string, description: "CronJobs", jsonPath: ".spec.cronjobs[*].name"},
        %{name: "Sleeping?", type: :string, description: "Current Status", jsonPath: ".status.conditions[?(@.type == \"Sleeping\")].status"},
        %{name: "Transitioning?", type: :string, description: "Status Change In Progress", jsonPath: ".status.conditions[?(@.type == \"Transitioning\")].status"},
        %{name: "ManualOverride?", type: :string, description: "Status overridden by user", jsonPath: ".status.conditions[?(@.type == \"ManualOverride\")].status"}
      ]
    )
    |> add_observed_generation_status()
    |> add_hosts_status()
    |> add_conditions()
  end

  defp add_hosts_status(version) do
    version
    |> put_in([Access.key(:subresources, %{}), :status], %{})
    |> put_in(
      [
        Access.key(:schema, %{}),
        Access.key(:openAPIV3Schema, %{type: :object}),
        Access.key(:properties, %{}),
        Access.key(:status, %{type: :object, properties: %{}}),
        Access.key(:properties, %{}),
        :hosts
      ],
      %{type: :array, items: %{type: :string}}
    )
  end
end
