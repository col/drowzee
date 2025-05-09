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
    annotations = get_in(statefulset, ["metadata", "annotations"]) || %{}
    current = get_in(statefulset, ["spec", "replicas"]) || 0
    current_str = Integer.to_string(current)

    # Only save if:
    # - annotation is missing OR
    # - annotation value != current AND current > 0
    # This way, if someone changed the replica count while awake, you update it before sleep
    case Map.get(annotations, "drowzee.io/original-replicas") do
      nil when current > 0 ->
        put_in(statefulset, ["metadata", "annotations", "drowzee.io/original-replicas"], current_str)
      value when value != current_str and current > 0 ->
        put_in(statefulset, ["metadata", "annotations", "drowzee.io/original-replicas"], current_str)
      _ ->
        statefulset
    end
  end

  @doc """
  Get the original replicas count from the annotation, as integer. Default to 1 if missing or invalid.
  """
  def get_original_replicas(statefulset) do
    annotations = get_in(statefulset, ["metadata", "annotations"]) || %{}
    case Map.get(annotations, "drowzee.io/original-replicas") do
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
