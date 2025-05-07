defmodule Drowzee.TransitionMonitor do
  @moduledoc """
  Drowzee: TransitionMonitor

  Monitors the status of a transition every 5 seconds.
  If the transition is complete, the periodic task is stopped.
  If the transition is not complete, the heartbeat is updated to trigger a :modify event to the SleepSchedule controller.
  The monitor will expire after 5 attempts (25 seconds). After that we'll rely on the reconcile loop to update the state.
  """

  require Logger

  def start_transition_monitor(name, namespace) do
    Logger.info("Monitoring transition...")
    task_name = "monitor_transition_#{name}_#{namespace}" |> String.to_atom()
    Bonny.PeriodicTask.unregister(task_name)
    Bonny.PeriodicTask.new(task_name, {Drowzee.TransitionMonitor, :monitor_transition, [name, namespace, 1]}, 30000)
  end

  def monitor_transition(name, namespace, attempt) do
    sleep_schedule = Drowzee.K8s.get_sleep_schedule!(name, namespace)
    case {Drowzee.K8s.SleepSchedule.get_condition(sleep_schedule, "Transitioning"), attempt} do
      {%{"status" => "False"}, _} ->
        Logger.warning("TransitionMonitor - Transition complete")
        {:stop, "Transition complete"}
      {_, attempt} when attempt > 5 ->
        Logger.warning("TransitionMonitor - Transition expired")
        {:stop, "Transition monitor expired after 5 attempts"}
      _ ->
        Logger.debug("Transition still running...")
        Logger.warning("TransitionMonitor - Transition still running...")
        Drowzee.K8s.SleepSchedule.update_heartbeat(sleep_schedule)
        {:ok, [name, namespace, attempt + 1]}
    end
  end
end
