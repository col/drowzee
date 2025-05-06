defmodule Drowzee.K8s.StatefulSet do
  require Logger

  def name(stateful_set) do
    stateful_set["metadata"]["name"]
  end

  def namespace(stateful_set) do
    stateful_set["metadata"]["namespace"]
  end

  def replicas(stateful_set) do
    stateful_set["spec"]["replicas"] || 0
  end

  def ready_replicas(stateful_set) do
    stateful_set["status"]["readyReplicas"] || 0
  end

  def scale_stateful_set(%{"kind" => "StatefulSet"} = stateful_set, replicas) do
    Logger.info("Scaling stateful set", stateful_set: name(stateful_set), replicas: replicas)
    stateful_set = put_in(stateful_set["spec"]["replicas"], replicas)
    case K8s.Client.run(Drowzee.K8s.conn(), K8s.Client.update(stateful_set)) do
      {:ok, stateful_set} -> {:ok, stateful_set}
      {:error, reason} ->
        Logger.error("Failed to scale stateful set: #{inspect(reason)}", stateful_set: name(stateful_set), replicas: replicas)
        {:error, reason}
    end
  end
end
