defmodule Drowzee.ConfigMap do
  def create_configmap(name, namespace, data) do
    %{
      "apiVersion" => "v1",
      "kind" => "ConfigMap",
      "metadata" => %{
        "name" => name,
        "namespace" => namespace
      },
      "data" => %{
        "ingress.json" => Jason.encode!(data)
      }
    }
  end
end
