defmodule Drowzee.K8s.SleepSchedule do
  use Retry.Annotation

  require Logger

  alias Drowzee.K8s.{Deployment, StatefulSet, CronJob, Ingress, Condition}

  def name(sleep_schedule) do
    sleep_schedule["metadata"]["name"]
  end

  def namespace(sleep_schedule) do
    sleep_schedule["metadata"]["namespace"]
  end

  def deployment_names(sleep_schedule) do
    (sleep_schedule["spec"]["deployments"] || [])
    |> Enum.map(& &1["name"])
  end

  def stateful_set_names(sleep_schedule) do
    (sleep_schedule["spec"]["statefulSets"] || [])
    |> Enum.map(& &1["name"])
  end

  def cron_job_names(sleep_schedule) do
    (sleep_schedule["spec"]["cronJobs"] || [])
    |> Enum.map(& &1["name"])
  end

  def ingress_name(sleep_schedule) do
    sleep_schedule["spec"]["ingressName"]
  end

  def get_condition(sleep_schedule, type) do
    (sleep_schedule["status"]["conditions"] || [])
    |> Enum.filter(&(&1["type"] == type))
    |> List.first()
  end

  def put_condition(sleep_schedule, type, status, reason \\ nil, message \\ nil) do
    sleep_schedule = Map.put(sleep_schedule, "status", sleep_schedule["status"] || %{})
    new_conditions = (sleep_schedule["status"]["conditions"] || [])
      |> Enum.filter(&(&1["type"] != type))
      |> List.insert_at(-1, Condition.new(type, status, reason, message))
    put_in(sleep_schedule, ["status", "conditions"], new_conditions)
  end

  def is_sleeping?(sleep_schedule) do
    (get_condition(sleep_schedule, "Sleeping") || %{})["status"] == "True"
  end

  def get_ingress(sleep_schedule) do
    case ingress_name(sleep_schedule) do
      nil -> {:error, :ingress_name_not_set}
      "" -> {:error, :ingress_name_not_set}
      ingress_name ->
        namespace = namespace(sleep_schedule)
        Logger.debug("Fetching ingress", ingress_name: ingress_name)
        K8s.Client.get("networking.k8s.io/v1", :ingress, name: ingress_name, namespace: namespace)
        |> K8s.Client.put_conn(Drowzee.K8s.conn())
        |> K8s.Client.run()
    end
  end

  @retry with: exponential_backoff(1000) |> Stream.take(2)
  def get_deployments(sleep_schedule) do
    namespace = namespace(sleep_schedule)
    results = (deployment_names(sleep_schedule) || [])
      |> Stream.map(&Drowzee.K8s.get_deployment(&1, namespace))
      |> Enum.to_list()

    case Enum.all?(results, fn {:ok, _} -> true; _ -> false end) do
      true -> {:ok, Enum.map(results, fn {:ok, deployment} -> deployment end)}
      false -> {:error, Enum.filter(results, fn {:error, _} -> true; _ -> false end) |> Enum.map(fn {:error, error} -> error end)}
    end
  end

  @retry with: exponential_backoff(1000) |> Stream.take(2)
  def get_stateful_sets(sleep_schedule) do
    namespace = namespace(sleep_schedule)
    results = (stateful_set_names(sleep_schedule) || [])
      |> Stream.map(&Drowzee.K8s.get_stateful_set(&1, namespace))
      |> Enum.to_list()

    case Enum.all?(results, fn {:ok, _} -> true; _ -> false end) do
      true -> {:ok, Enum.map(results, fn {:ok, stateful_set} -> stateful_set end)}
      false -> {:error, Enum.filter(results, fn {:error, _} -> true; _ -> false end) |> Enum.map(fn {:error, error} -> error end)}
    end
  end

  @retry with: exponential_backoff(1000) |> Stream.take(2)
  def get_cron_jobs(sleep_schedule) do
    namespace = namespace(sleep_schedule)
    results = (cron_job_names(sleep_schedule) || [])
      |> Stream.map(&Drowzee.K8s.get_cron_job(&1, namespace))
      |> Enum.to_list()

    case Enum.all?(results, fn {:ok, _} -> true; _ -> false end) do
      true -> {:ok, Enum.map(results, fn {:ok, cron_job} -> cron_job end)}
      false -> {:error, Enum.filter(results, fn {:error, _} -> true; _ -> false end) |> Enum.map(fn {:error, error} -> error end)}
    end
  end

  def scale_down_deployments(sleep_schedule) do
    Logger.debug("Scaling down deployments...")
    case get_deployments(sleep_schedule) do
      {:ok, deployments} ->
        results = Enum.map(deployments, &Deployment.scale_deployment(&1, 0))
        {:ok, results}
      {:error, error} ->
        {:error, error}
    end
  end

  def scale_down_stateful_sets(sleep_schedule) do
    Logger.debug("Scaling down stateful sets...")
    case get_stateful_sets(sleep_schedule) do
      {:ok, stateful_sets} ->
        results = Enum.map(stateful_sets, &StatefulSet.scale_stateful_set(&1, 0))
        {:ok, results}
      {:error, error} ->
        {:error, error}
    end
  end

  def suspend_cron_jobs(sleep_schedule) do
    Logger.debug("Suspending cron jobs...")
    case get_cron_jobs(sleep_schedule) do
      {:ok, cron_jobs} ->
        results = Enum.map(cron_jobs, &CronJob.suspend_cron_job(&1, true))
        {:ok, results}
      {:error, error} ->
        {:error, error}
    end
  end

  def scale_up_deployments(sleep_schedule) do
    Logger.debug("Scaling up deployments...")
    case get_deployments(sleep_schedule) do
      {:ok, deployments} ->
        results = Enum.map(deployments, &Deployment.scale_deployment(&1, 1))
        {:ok, results}
      {:error, error} ->
        {:error, error}
    end
  end

  def scale_up_stateful_sets(sleep_schedule) do
    Logger.debug("Scaling up stateful sets...")
    case get_stateful_sets(sleep_schedule) do
      {:ok, stateful_sets} ->
        results = Enum.map(stateful_sets, &StatefulSet.scale_stateful_set(&1, 1))
        {:ok, results}
      {:error, error} ->
        {:error, error}
    end
  end

  def resume_cron_jobs(sleep_schedule) do
    Logger.debug("Resuming cron jobs...")
    case get_cron_jobs(sleep_schedule) do
      {:ok, cron_jobs} ->
        results = Enum.map(cron_jobs, &CronJob.suspend_cron_job(&1, false))
        {:ok, results}
      {:error, error} ->
        {:error, error}
    end
  end

  def put_ingress_to_sleep(sleep_schedule) do
    with {:ok, ingress} <- get_ingress(sleep_schedule),
        {:ok, drowzee_ingress} <- Drowzee.K8s.get_drowzee_ingress(),
        {:ok, updated_ingress} <- Ingress.add_redirect_annotation(ingress, sleep_schedule, drowzee_ingress),
        {:ok, _} <- K8s.Client.run(Drowzee.K8s.conn(), K8s.Client.update(updated_ingress)) do
      {:ok, updated_ingress}
    else
      {:error, error} ->
        {:error, error}
    end
  end

  def wake_up_ingress(sleep_schedule) do
    with {:ok, ingress} <- get_ingress(sleep_schedule),
         {:ok, updated_ingress} <- Ingress.remove_redirect_annotation(ingress),
         {:ok, _} <- K8s.Client.run(Drowzee.K8s.conn(), K8s.Client.update(updated_ingress)) do
      {:ok, updated_ingress}
    else
      {:error, error} ->
        {:error, error}
    end
  end

  def update_heartbeat(sleep_schedule) do
    Logger.debug("Update heartbeat...")
    heartbeat = get_condition(sleep_schedule, "Heartbeat") || %{ "status" => "False" }
    put_condition(
      sleep_schedule,
      "Heartbeat",
      (if heartbeat["status"] == "True", do: "False", else: "True"),
      "StayingAlive",
      "Triggers events from transition monitor"
    )
    |> Drowzee.K8s.decrement_observed_generation()
    |> Bonny.Resource.apply_status(Drowzee.K8s.conn())
  end
end
