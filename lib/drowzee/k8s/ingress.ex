defmodule Drowzee.K8s.Ingress do
  def get_hosts(ingress) do
    (ingress["spec"]["rules"] || [])
    |> Enum.map(fn rule ->
      rule["host"]
    end)
  end
end
