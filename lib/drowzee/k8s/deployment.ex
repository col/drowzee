defmodule Drowzee.K8s.Deployment do
  require Logger

  def name(deployment), do: deployment["metadata"]["name"]

  def namespace(deployment), do: deployment["metadata"]["namespace"]

  def replicas(deployment), do: deployment["spec"]["replicas"] || 0

  def ready_replicas(deployment), do: deployment["status"]["readyReplicas"] || 0

  @doc """
  Always save (or update) the current replica count as an annotation on the deployment.
  """
  def save_original_replicas(deployment) do
    annotations = get_in(deployment, ["metadata", "annotations"]) || %{}
    current = get_in(deployment, ["spec", "replicas"]) || 0
    current_str = Integer.to_string(current)

    # Only save if:
    # - annotation is missing OR
    # - annotation value != current AND current > 0
    # This way, if someone changed the replica count while awake, you update it before sleep
    case Map.get(annotations, "drowzee.io/original-replicas") do
      nil when current > 0 ->
        put_in(deployment, ["metadata", "annotations", "drowzee.io/original-replicas"], current_str)
      value when value != current_str and current > 0 ->
        put_in(deployment, ["metadata", "annotations", "drowzee.io/original-replicas"], current_str)
      _ ->
        deployment
    end
  end

  @doc """
  Get the original replicas count from the annotation, as integer. Default to 1 if missing or invalid.
  """
  def get_original_replicas(deployment) do
    annotations = get_in(deployment, ["metadata", "annotations"]) || %{}
    case Map.get(annotations, "drowzee.io/original-replicas") do
      nil -> 1
      value ->
        case Integer.parse(value) do
          {count, _} -> count
          :error -> 1
        end
    end
  end

  def scale_deployment(%{"kind" => "Deployment"} = deployment, replicas) do
    Logger.info("Scaling deployment", name: name(deployment), replicas: replicas)
    deployment = put_in(deployment["spec"]["replicas"], replicas)
    case K8s.Client.run(Drowzee.K8s.conn(), K8s.Client.update(deployment)) do
      {:ok, deployment} -> {:ok, deployment}
      {:error, reason} ->
        Logger.error("Failed to scale deployment: #{inspect(reason)}", name: name(deployment), replicas: replicas)
        {:error, reason}
    end
  end
end
