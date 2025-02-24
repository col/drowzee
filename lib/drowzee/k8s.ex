defmodule Drowzee.K8s do

  def sleep_schedule_list(namespace \\ nil) do
    operation = K8s.Client.list("drowzee.challengr.io/v1beta1", "SleepSchedule", namespace: namespace)
    K8s.Client.run(conn(), operation)
  end

  def sleep_schedules(namespace \\ nil) do
    case sleep_schedule_list(namespace) do
      {:ok, list} -> list["items"]
      {:error, _error} -> []
    end
  end

  def get_sleep_schedule(name, namespace \\ nil) do
    operation = K8s.Client.get("drowzee.challengr.io/v1beta1", "SleepSchedule", name: name, namespace: namespace)
    K8s.Client.run(conn(), operation)
  end

  def get_sleep_schedule!(name, namespace \\ nil) do
    {:ok, sleep_schedule} = get_sleep_schedule(name, namespace)
    sleep_schedule
  end

  def manual_wake_up(sleep_schedule) do
    sleep_schedule = Drowzee.K8s.SleepSchedule.put_condition(
      sleep_schedule,
      "ManualOverride",
      true,
      "WakeUp",
      "Force deployments to wake up"
    )
    # Make sure we handle the modify event rather then wait for a reconcile
    |> decrement_observed_generation()

    Bonny.Resource.apply_status(sleep_schedule, conn(), force: true)
  end

  def manual_sleep(sleep_schedule) do
    sleep_schedule = Drowzee.K8s.SleepSchedule.put_condition(
      sleep_schedule,
      "ManualOverride",
      true,
      "Sleep",
      "Force deployments to sleep"
    )
    # Make sure we handle the modify event rather then wait for a reconcile
    |> decrement_observed_generation()

    Bonny.Resource.apply_status(sleep_schedule, conn(), force: true)
  end

  def decrement_observed_generation(resource) do
    generation = get_in(resource, [Access.key("status", %{}), "observedGeneration"])
    put_in(resource, [Access.key("status", %{}), "observedGeneration"], generation - 1)
  end

  def conn() do
    Drowzee.K8sConn.get!()
  end
end
