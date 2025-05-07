defmodule Drowzee.K8s.CronJob do
  require Logger

  def name(cronjob) do
    cronjob["metadata"]["name"]
  end

  def namespace(cronjob) do
    cronjob["metadata"]["namespace"]
  end

  def suspend(cronjob) do
    cronjob["spec"]["suspend"] || false
  end

  def suspend_cronjob(%{"kind" => "CronJob"} = cronjob, suspend) do
    Logger.info("Setting cronjob suspend", name: name(cronjob), suspend: suspend)
    cronjob = put_in(cronjob["spec"]["suspend"], suspend)
    case K8s.Client.run(Drowzee.K8s.conn(), K8s.Client.update(cronjob)) do
      {:ok, cronjob} -> {:ok, cronjob}
      {:error, reason} ->
        Logger.error("Failed to suspend cronjob: #{inspect(reason)}", name: name(cronjob), suspend: suspend)
        {:error, reason}
    end
  end
end
