defmodule Drowzee.ConfigMap do
  require Logger

  def create_configmap(name, namespace, data) do
    ingress_data = Jason.encode!(data)
    %{
      "apiVersion" => "v1",
      "kind" => "ConfigMap",
      "metadata" => %{
        "name" => name,
        "namespace" => namespace,

      },
      "data" => %{
        "ingress.json" => ingress_data,
        "checksum" => :crypto.hash(:md5, ingress_data) |> Base.encode64()
      }
    }
  end

  def update_required?(configmap, ingress) do
    ingress_data = Jason.encode!(ingress)
    checksum = :crypto.hash(:md5, ingress_data) |> Base.encode64()
    (configmap["data"]["checksum"] || "") != checksum
  end
end
