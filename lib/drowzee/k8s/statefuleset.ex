defmodule Drowzee.K8s.StatefulSet do
  require Logger

  def name(statefulset), do: statefulset["metadata"]["name"]

  def namespace(statefulset), do: statefulset["metadata"]["namespace"]

  def replicas(statefulset), do: statefulset["spec"]["replicas"] || 0

  def ready_replicas(statefulset), do: statefulset["status"]["readyReplicas"] || 0

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
