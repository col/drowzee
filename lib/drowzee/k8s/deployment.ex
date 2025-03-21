defmodule Drowzee.K8s.Deployment do
  require Logger

  def name(deployment) do
    deployment["metadata"]["name"]
  end

  def namespace(deployment) do
    deployment["metadata"]["namespace"]
  end

  def replicas(deployment) do
    deployment["spec"]["replicas"] || 0
  end

  def ready_replicas(deployment) do
    deployment["status"]["readyReplicas"] || 0
  end

  def scale_deployment(%{"kind" => "Deployment"} = deployment, replicas) do
    Logger.info("Scaling deployment", deployment: name(deployment), replicas: replicas)
    deployment = put_in(deployment["spec"]["replicas"], replicas)
    case K8s.Client.run(Drowzee.K8s.conn(), K8s.Client.update(deployment)) do
      {:ok, deployment} -> {:ok, deployment}
      {:error, reason} ->
        Logger.error("Failed to scale deployment: #{inspect(reason)}", deployment: name(deployment), replicas: replicas)
        {:error, reason}
    end
  end
end
