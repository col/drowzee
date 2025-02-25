defmodule DrowzeeWeb.RedirectController do
  use DrowzeeWeb, :controller

  require Logger

  def redirect_to_sleep_schedule(conn, _params) do
    Logger.info("Finding sleep schedule for host: #{conn.host}")

    sleep_schedule = (Drowzee.K8s.sleep_schedules() || [])
      |> Enum.find(fn sleep_schedule -> Enum.any?((sleep_schedule["status"]["hosts"] || []), &(&1 == conn.host)) end)

    if sleep_schedule == nil do
      Logger.warning("No sleep schedule found for host: #{conn.host}. Redirecting to '/'")
      redirect(conn, to: "/all")
    else
      namespace = sleep_schedule["metadata"]["namespace"]
      name = sleep_schedule["metadata"]["name"]
      Logger.info("Found sleep schedule: '#{namespace}/#{name}' for host '#{conn.host}'. Redirecting to '/#{namespace}/#{name}'")
      redirect(conn, to: "/#{namespace}/#{name}")
    end
  end
end
