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

  @impl true
  def manifest() do
    defaults()
    |> struct!(name: "v1beta1")
    |> add_observed_generation_status()
  end
end
