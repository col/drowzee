defmodule Drowzee.K8s.StatefulSet do
  require Logger

  def name(statefulset), do: statefulset["metadata"]["name"]

  def namespace(statefulset), do: statefulset["metadata"]["namespace"]

  def replicas(statefulset), do: statefulset["spec"]["replicas"] || 0

  def ready_replicas(statefulset), do: statefulset["status"]["readyReplicas"] || 0

  @doc """
  Always save (or update) the current replica count as an annotation on the statefulset.
  """
  def save_original_replicas(statefulset) do
    current = get_in(statefulset, ["spec", "replicas"]) || 0
    put_in(statefulset, ["metadata", "annotations", "drowzee.chirpwireless.io/original-replicas"], Integer.to_string(current))
  end

  @doc """
  Get the original replicas count from the annotation, as integer. Default to 1 if missing or invalid.
  """
  def get_original_replicas(statefulset) do
    annotations = get_in(statefulset, ["metadata", "annotations"]) || %{}
    case Map.get(annotations, "drowzee.chirpwireless.io/original-replicas") do
      nil -> 1
      value ->
        case Integer.parse(value) do
          {count, _} -> count
          :error -> 1
        end
    end
  end

  def scale_statefulset(%{"kind" => "StatefulSet"} = statefulset, replicas) do
    Logger.info("Scaling statefulset", name: name(statefulset), replicas: replicas)
    statefulset = put_in(statefulset["spec"]["replicas"], replicas)
    case K8s.Client.run(Drowzee.K8s.conn(), K8s.Client.update(statefulset)) do
      {:ok, statefulset} -> {:ok, statefulset}
      {:error, reason} ->
        Logger.error("Failed to scale statefulset: #{inspect(reason)}", name: name(statefulset), replicas: replicas)
        {:error, reason}
    end
  end
end
