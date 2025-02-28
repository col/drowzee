defmodule Drowzee.K8s do
  require Logger

  def sleep_schedule_list(namespace \\ Bonny.Config.namespace()) do
    K8s.Client.list("drowzee.challengr.io/v1beta1", "SleepSchedule", namespace: namespace)
    |> K8s.Client.put_conn(conn())
    |> K8s.Client.run()
  end

  def sleep_schedules(namespace \\ nil) do
    case sleep_schedule_list(namespace) do
      {:ok, list} -> list["items"]
      {:error, _error} -> []
    end
  end

  def get_sleep_schedule(name, namespace \\ Bonny.Config.namespace()) do
    K8s.Client.get("drowzee.challengr.io/v1beta1", "SleepSchedule", name: name, namespace: namespace)
    |> K8s.Client.put_conn(conn())
    |> K8s.Client.run()
  end

  def get_sleep_schedule!(name, namespace \\ nil) do
    {:ok, sleep_schedule} = get_sleep_schedule(name, namespace)
    sleep_schedule
  end

  def manual_wake_up(sleep_schedule) do
    Drowzee.K8s.SleepSchedule.put_condition(
      sleep_schedule,
      "ManualOverride",
      true,
      "WakeUp",
      "Force deployments to wake up"
    )
    |> decrement_observed_generation() # Make sure we handle the modify event rather then wait for a reconcile
    |> Bonny.Resource.apply_status(conn(), force: true)
  end

  def manual_sleep(sleep_schedule) do
    Drowzee.K8s.SleepSchedule.put_condition(
      sleep_schedule,
      "ManualOverride",
      true,
      "Sleep",
      "Force deployments to sleep"
    )
    |> decrement_observed_generation() # Make sure we handle the modify event rather then wait for a reconcile
    |> Bonny.Resource.apply_status(conn(), force: true)
  end

  def remove_override(sleep_schedule) do
    Drowzee.K8s.SleepSchedule.put_condition(
      sleep_schedule,
      "ManualOverride",
      false,
      "NoOverride",
      "No manual override in effect"
    )
    |> decrement_observed_generation() # Make sure we handle the modify event rather then wait for a reconcile
    |> Bonny.Resource.apply_status(conn(), force: true)
  end

  def decrement_observed_generation(resource) do
    generation = get_in(resource, [Access.key("status", %{}), "observedGeneration"])
    put_in(resource, [Access.key("status", %{}), "observedGeneration"], generation - 1)
  end

  def conn() do
    Drowzee.K8sConn.get!()
  end

  def get_drowzee_ingress() do
    name = "drowzee"
    namespace = drowzee_namespace()
    Logger.debug("Fetching drowzee ingress", ingress_name: name, drowzee_namespace: namespace)
    K8s.Client.get("networking.k8s.io/v1", :ingress, name: name, namespace: namespace)
    |> K8s.Client.put_conn(conn())
    |> K8s.Client.run()
  end

  @default_service_account_path "/var/run/secrets/kubernetes.io/serviceaccount"

  def drowzee_namespace() do
    namespace_path = Path.join(@default_service_account_path, "namespace")
    case File.read(namespace_path) do
      {:ok, namespace} -> namespace
      _ -> Application.get_env(:drowzee, :drowzee_namespace, "default")
    end
  end

  def get_deployment(name, namespace) do
    Logger.debug("Fetching deployment", deployment_name: name)
    K8s.Client.get("apps/v1", :deployment, name: name, namespace: namespace)
    |> K8s.Client.put_conn(conn())
    |> K8s.Client.run()
  end
end
