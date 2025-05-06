defmodule Drowzee.K8s.CronJob do
  require Logger

  def name(cron_job) do
    cron_job["metadata"]["name"]
  end

  def namespace(cron_job) do
    cron_job["metadata"]["namespace"]
  end

  def suspend(cron_job) do
    cron_job["spec"]["suspend"] || false
  end

  def suspend_cron_job(%{"kind" => "CronJob"} = cron_job, suspend) do
    Logger.info("Setting cron job suspend", cron_job: name(cron_job), suspend: suspend)
    cron_job = put_in(cron_job["spec"]["suspend"], suspend)
    case K8s.Client.run(Drowzee.K8s.conn(), K8s.Client.update(cron_job)) do
      {:ok, cron_job} -> {:ok, cron_job}
      {:error, reason} ->
        Logger.error("Failed to suspend cron job: #{inspect(reason)}", cron_job: name(cron_job), suspend: suspend)
        {:error, reason}
    end
  end
end
