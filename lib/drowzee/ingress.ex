defmodule Drowzee.Ingress do

  # Updates the ingress to point to the service
  def update_for_service(ingress, service) do
    ingress = ingress
      |> put_in(["spec", "rules", Access.all(), "http", "paths", Access.all(), "backend", "service", "name"], service["metadata"]["name"])
      |> put_in(["spec", "rules", Access.all(), "http", "paths", Access.all(), "backend", "service", "port", "number"], hd(service["spec"]["ports"])["port"])
    {:ok, ingress}
  end

  def add_sleeping_annotation(ingress) do
    ingress = put_in(ingress, ["metadata", "annotations", "drowzee.challengr.io/sleeping"], "True")
    {:ok, ingress}
  end

  def remove_sleeping_annotation(ingress) do
    ingress = put_in(ingress, ["metadata", "annotations", "drowzee.challengr.io/sleeping"], "False")
    {:ok, ingress}
  end

  def sleeping_annotation?(ingress) do
    Map.get(ingress["metadata"]["annotations"], "drowzee.challengr.io/sleeping", "False") == "True"
  end
end
