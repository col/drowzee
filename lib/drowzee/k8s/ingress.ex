defmodule Drowzee.K8s.Ingress do
  alias Drowzee.K8s.Ingress

  def get_hosts(ingress) do
    (ingress["spec"]["rules"] || [])
    |> Enum.map(fn rule ->
      rule["host"]
    end)
  end

  def add_redirect_annotation(ingress, sleep_schedule, drowzee_ingress) do
    path = "#{sleep_schedule["metadata"]["namespace"]}/#{sleep_schedule["metadata"]["name"]}"
    hosts = Ingress.get_hosts(drowzee_ingress)
    base_url = "http://#{List.first(hosts) || "unknown"}"
    ingress = put_in(ingress, ["metadata", "annotations", "nginx.ingress.kubernetes.io/temporal-redirect"], "#{base_url}/#{path}")
    {:ok, ingress}
  end

  def remove_redirect_annotation(ingress) do
    ingress = put_in(ingress, ["metadata", "annotations", "nginx.ingress.kubernetes.io/temporal-redirect"], "")
    {:ok, ingress}
  end

  def redirect_annotation?(ingress) do
    Map.get(ingress["metadata"]["annotations"], "nginx.ingress.kubernetes.io/temporal-redirect", "") != ""
  end
end
