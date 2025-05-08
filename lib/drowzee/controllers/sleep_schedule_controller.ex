defmodule Drowzee.Controller.SleepScheduleController do
  @moduledoc """
  Drowzee: SleepScheduleController controller.
  """

  use Bonny.ControllerV2
  import Drowzee.Axn
  require Logger
  alias Drowzee.K8s.{SleepSchedule, Ingress, Deployment, StatefulSet, CronJob}

  step Bonny.Pluggable.SkipObservedGenerations
  step :handle_event

  def handle_event(%Bonny.Axn{resource: %{"spec" => spec}} = axn, _opts) do
    if Map.get(spec, "enabled", true) == false do
      Logger.info("Schedule #{axn.resource["metadata"]["name"]} is disabled. Skipping.")
      axn
    else
      handle_event_enabled(axn, _opts)
    end
  end

  def handle_event_enabled(%Bonny.Axn{action: action} = axn, _opts)
      when action in [:add, :modify, :reconcile] do
    Logger.metadata(
      schedule: axn.resource["metadata"]["name"],
      namespace: axn.resource["metadata"]["namespace"]
    )
    axn
    |> add_default_conditions()
    |> set_naptime_assigns()
    |> update_state()
    |> publish_event() # TODO: Only publish an event when something changes
    |> success_event()
  end

  # delete the resource
  def handle_event_enabled(%Bonny.Axn{action: :delete} = axn, _opts) do
    Logger.warning("Delete Action - Not yet implemented!")
    # TODO:
    # - Make sure deployments are awake
    axn
  end

  defp publish_event(axn) do
    Task.start(fn ->
      Process.sleep(500)
      Phoenix.PubSub.broadcast(Drowzee.PubSub, "sleep_schedule:updates", {:sleep_schedule_updated})
    end)
    axn
  end

  defp add_default_conditions(axn) do
    axn
    |> set_default_condition("Sleeping", false, "InitialValue", "New wake schedule")
    |> set_default_condition("Transitioning", false, "NoTransition", "No transition in progress")
    |> set_default_condition("ManualOverride", false, "NoManualOverride", "No manual override present")
    |> set_default_condition("Error", false, "NoError", "No error present")
    |> set_default_condition("Heartbeat", false, "StayingAlive", "Triggers events from transition monitor")
  end

  defp set_naptime_assigns(%Bonny.Axn{resource: resource} = axn) do
    sleep_time = resource["spec"]["sleepTime"]
    wake_time = resource["spec"]["wakeTime"]
    timezone = resource["spec"]["timezone"]

    # Log if wake_time is not defined (resources will remain down indefinitely)
    if is_nil(wake_time) or wake_time == "" do
      Logger.info("Wake time is not defined for #{resource["metadata"]["name"]} in namespace #{resource["metadata"]["namespace"]}. Resources will remain scaled down/suspended indefinitely.")
    end

    case Drowzee.SleepChecker.naptime?(sleep_time, wake_time, timezone) do
      {:ok, naptime} ->
        %{axn | assigns: Map.put(axn.assigns, :naptime, naptime)}
      {:error, reason} ->
        Logger.error("Error checking naptime: #{reason}")
        set_condition(axn, "Error", true, "InvalidSleepSchedule", "Invalid sleep schedule: #{reason}")
    end
  end

  defp update_state(%Bonny.Axn{} = axn) do
    with {:ok, sleeping} <- get_condition(axn, "Sleeping"),
         {:ok, transitioning} <- get_condition(axn, "Transitioning"),
         {:ok, manual_override} <- get_condition(axn, "ManualOverride") do

      naptime = if axn.assigns[:naptime], do: :naptime, else: :not_naptime
      sleeping_value = if sleeping["status"] == "True", do: :sleeping, else: :awake
      transitioning_value = if transitioning["status"] == "True", do: :transition, else: :no_transition
      manual_override_value = case {manual_override["status"], manual_override["reason"]} do
        {"True", "WakeUp"} -> :wake_up_override
        {"True", "Sleep"} -> :sleep_override
        {_, _} -> :no_override
      end

      Logger.debug(inspect({sleeping_value, transitioning_value, manual_override_value, naptime}, label: "Updating state with:"))
      case {sleeping_value, transitioning_value, manual_override_value, naptime} do
        # Trigger action from manual override
        {:awake, :no_transition, :sleep_override, _} -> initiate_sleep(axn)
        {:sleeping, :no_transition, :wake_up_override, _} -> initiate_wake_up(axn)
        # Clear manual overrides once they're no longer needed
        {:awake, :no_transition, :wake_up_override, :not_naptime} -> axn |> clear_manual_override()
        {:sleeping, :no_transition, :sleep_override, :naptime} -> axn |> clear_manual_override()
        # Trigger scheduled actions
        {:awake, :no_transition, :no_override, :naptime} -> initiate_sleep(axn)
        {:sleeping, :no_transition, :no_override, :not_naptime} -> initiate_wake_up(axn)
        # Await transitions (could be moved to background process)
        {:awake, :transition, _, _} -> check_sleep_transition(axn, manual_override: manual_override_value != :no_override)
        {:sleeping, :transition, _, _} -> check_wake_up_transition(axn, manual_override: manual_override_value != :no_override)
        {_, _, _, _} ->
          Logger.debug("No action required for current state.")
          axn
      end
    else
      {:error, _error} -> axn # Conditions should be present except for the first event
    end
  end

  defp clear_manual_override(axn) do
    Logger.info("Clearing manual override")
    set_condition(axn, "ManualOverride", false, "NoOverride", "No manual override in effect")
  end

  defp initiate_sleep(axn) do
    Logger.info("Initiating sleep")
    axn
    |> update_hosts()
    |> set_condition("Transitioning", true, "Sleeping", "Going to sleep")
    |> scale_down_deployments()
    |> start_transition_monitor()
  end

  defp initiate_wake_up(axn) do
    Logger.info("Initiating wake up")
    axn
    |> set_condition("Transitioning", true, "WakingUp", "Waking up")
    |> scale_up_deployments()
    |> start_transition_monitor()
  end

  defp start_transition_monitor(axn) do
    Drowzee.TransitionMonitor.start_transition_monitor(axn.resource["metadata"]["name"], axn.resource["metadata"]["namespace"])
    axn
  end

  defp scale_down_deployments(axn) do
    SleepSchedule.scale_down_deployments(axn.resource)
    SleepSchedule.scale_down_statefulsets(axn.resource)
    SleepSchedule.suspend_cronjobs(axn.resource)
    axn
  end

  defp scale_up_deployments(axn) do
    SleepSchedule.scale_up_deployments(axn.resource)
    SleepSchedule.scale_up_statefulsets(axn.resource)
    SleepSchedule.resume_cronjobs(axn.resource)
    axn
  end

  defp update_hosts(axn) do
    case SleepSchedule.get_ingress(axn.resource) do
      {:ok, ingress} ->
        update_status(axn, fn status ->
          Map.put(status, "hosts", Ingress.get_hosts(ingress))
        end)
      {:error, :ingress_name_not_set} ->
        update_status(axn, fn status ->
          Map.put(status, "hosts", [])
        end)
      {:error, error} ->
        Logger.error("Failed to get ingress: #{inspect(error)}")
        axn
    end
  end

  defp check_sleep_transition(axn, opts) do
    Logger.info("Checking sleep transition...")
    case check_deployment_status(axn, &deployment_status_asleep?/1) do
      {:ok, true} ->
        Logger.debug("All deployments are asleep")
        axn
        |> put_ingress_to_sleep()
        |> complete_sleep_transition(opts)
      {:ok, false} ->
        Logger.debug("Deployments have not yet scaled down...")
        scale_down_deployments(axn)
      {:error, [error | _]} ->
        Logger.error("Failed to check deployment status: #{inspect(error)}")
        set_condition(axn, "Error", true, "DeploymentNotFound", error.message)
      {:error, error} ->
        Logger.error("Failed to check deployment status: #{inspect(error)}")
        axn
    end
  end

  defp check_wake_up_transition(axn, opts) do
    Logger.info("Checking wake up transition...")
    case check_deployment_status(axn, &deployment_status_ready?/1) do
      {:ok, true} ->
        Logger.debug("All deployments are ready")
        axn
        |> wake_up_ingress()
        |> complete_wake_up_transition(opts)
      {:ok, false} ->
        Logger.debug("Deployments are not ready...")
        scale_up_deployments(axn)
      {:error, [error | _]} ->
        Logger.error("Failed to check deployment status: #{inspect(error)}")
        set_condition(axn, "Error", true, "DeploymentNotFound", error.message)
      {:error, error} ->
        Logger.error("Failed to check deployment status: #{inspect(error)}")
        axn
    end
  end

  defp deployment_status_ready?(status) do
    replicas = Map.get(status, "replicas")
    ready_replicas = Map.get(status, "readyReplicas")
    suspended = Map.get(status, "suspended", true)

    cond do
      not is_nil(replicas) and not is_nil(ready_replicas) ->
        replicas == ready_replicas

      true ->
        # For CronJobs: considered ready if not suspended
        suspended == false
    end
  end

  defp deployment_status_asleep?(status) do
    replicas = Map.get(status, "replicas", 0)
    ready = Map.get(status, "readyReplicas", 0)
    suspended = Map.get(status, "suspended", nil)

    cond do
      not is_nil(suspended) ->
        suspended == true

      true ->
        replicas == 0 and ready == 0
    end
  end

  defp check_deployment_status(axn, check_fn) do
    with {:ok, deployments} <- SleepSchedule.get_deployments(axn.resource),
         {:ok, statefulsets} <- SleepSchedule.get_statefulsets(axn.resource),
         {:ok, cronjobs} <- SleepSchedule.get_cronjobs(axn.resource) do

      deployments_result =
        Enum.all?(deployments, fn deployment ->
          Logger.debug(
            "Deployment #{Deployment.name(deployment)} replicas: #{Deployment.replicas(deployment)}, readyReplicas: #{Deployment.ready_replicas(deployment)}"
          )

          check_fn.(deployment["status"])
        end)

      statefulsets_result =
        Enum.all?(statefulsets, fn statefulset ->
          Logger.debug(
            "StatefulSet #{StatefulSet.name(statefulset)} replicas: #{StatefulSet.replicas(statefulset)}, readyReplicas: #{StatefulSet.ready_replicas(statefulset)}"
          )

          check_fn.(statefulset["status"])
        end)

      cronjobs_result =
      Enum.all?(cronjobs, fn cronjob ->
        suspended = CronJob.suspend(cronjob)

        Logger.debug("CronJob #{CronJob.name(cronjob)} suspended: #{suspended}")

        # check_fn determines if suspended is the expected state (true for sleep, false for wake)
        check_fn.(%{"suspended" => suspended})
      end)

      # Determine which resources we need to check based on what's present
      has_deployments   = Enum.any?(deployments)
      has_statefulsets  = Enum.any?(statefulsets)
      has_cronjobs     = Enum.any?(cronjobs)

      case {has_deployments, has_statefulsets, has_cronjobs} do
        {false, false, false} -> {:ok, true}
        {true,  false, false} -> {:ok, deployments_result}
        {false, true,  false} -> {:ok, statefulsets_result}
        {false, false, true}  -> {:ok, cronjobs_result}
        {true,  true,  false} -> {:ok, deployments_result && statefulsets_result}
        {true,  false, true}  -> {:ok, deployments_result && cronjobs_result}
        {false, true,  true}  -> {:ok, statefulsets_result && cronjobs_result}
        {true,  true,  true}  -> {:ok, deployments_result && statefulsets_result && cronjobs_result}
      end
    else
      {:error, error} -> {:error, error}
    end
  end

  defp complete_sleep_transition(axn, opts) do
    Logger.info("Sleep transition complete")
    manual_override = Keyword.get(opts, :manual_override, false)
    wake_time = axn.resource["spec"]["wakeTime"]
    permanent_sleep = is_nil(wake_time) or wake_time == ""

    sleep_reason = cond do
      manual_override -> "ManualSleep"
      permanent_sleep -> "PermanentSleep"
      true -> "ScheduledSleep"
    end

    sleep_message = if permanent_sleep do
      "Deployments, StatefulSets, and CronJobs have been scaled down/suspended indefinitely and ingress redirected."
    else
      "Deployments, StatefulSets, and CronJobs have been scaled down/suspended and ingress redirected."
    end

    axn
      |> set_condition("Transitioning", false, "NoTransition", "No transition in progress")
      |> set_condition("Sleeping", true, sleep_reason, sleep_message)
      |> set_condition("Error", false, "None", "No error")
  end

  defp complete_wake_up_transition(axn, opts) do
    Logger.info("Wake up transition complete")
    manual_override = Keyword.get(opts, :manual_override, false)
    wake_reason = if manual_override, do: "ManualWakeUp", else: "ScheduledWakeUp"
    axn
      |> set_condition("Transitioning", false, "NoTransition", "No transition in progress")
      |> set_condition("Sleeping", false, wake_reason, "Deployments and StatefulSets have been scaled up, CronJobs have been resumed, and ingress restored.")
      |> set_condition("Error", false, "None", "No error")
  end

  defp put_ingress_to_sleep(axn) do
    case SleepSchedule.put_ingress_to_sleep(axn.resource) do
      {:ok, _} ->
        Logger.info("Updated ingress to redirect to Drowzee", name: SleepSchedule.ingress_name(axn.resource))
        # register_event(axn, nil, :Normal, "SleepIngress", "Ingress has been redirected to Drowzee")
        axn
      {:error, :ingress_name_not_set} ->
        Logger.info("No ingressName has been provided so there is nothing to redirect")
        axn
      {:error, error} ->
        Logger.error("Failed to redirect ingress to Drowzee: #{inspect(error)}", name: SleepSchedule.ingress_name(axn.resource))
        axn
    end
  end

  defp wake_up_ingress(axn) do
    case SleepSchedule.wake_up_ingress(axn.resource) do
      {:ok, _} ->
        Logger.info("Removed Drowzee redirect from ingress", name: SleepSchedule.ingress_name(axn.resource))
        # register_event(axn, nil, :Normal, "WakeUpIngress", "Ingress has been restored")
        axn
      {:error, :ingress_name_not_set} ->
        Logger.info("No ingressName has been provided so there is nothing to restore")
        axn
      {:error, error} ->
        Logger.error("Failed to remove Drowzee redirect from ingress: #{inspect(error)}", name: SleepSchedule.ingress_name(axn.resource))
        axn
    end
  end
end
