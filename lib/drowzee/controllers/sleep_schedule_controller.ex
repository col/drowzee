defmodule Drowzee.Controller.SleepScheduleController do
  @moduledoc """
  Drowzee: SleepScheduleController controller.

  """
  use Bonny.ControllerV2
  import Drowzee.Axn
  require Logger

  step Bonny.Pluggable.SkipObservedGenerations
  step :handle_event

  def handle_event(%Bonny.Axn{action: action} = axn, _opts)
      when action in [:add, :modify, :reconcile] do
    Logger.metadata(
      name: axn.resource["metadata"]["name"],
      namespace: axn.resource["metadata"]["namespace"]
    )
    axn
    |> add_default_conditions()
    |> set_naptime_assigns()
    |> update_state()
    |> publish_event()
    |> success_event()
  end

  # delete the resource
  def handle_event(%Bonny.Axn{action: :delete} = axn, _opts) do
    Logger.warning("Delete Action - Not yet implemented!")
    # TODO:
    # - Make sure deployments are awake
    axn
  end

  defp publish_event(axn) do
    Phoenix.PubSub.broadcast(Drowzee.PubSub, "sleep_schedule:updates", {:sleep_schedule_updated})
    axn
  end

  defp add_default_conditions(axn) do
    axn
    |> set_default_condition("Sleeping", false, "InitialValue", "New wake schedule")
    |> set_default_condition("Transitioning", false, "NoTransition", "No transition in progress")
    |> set_default_condition("ManualOverride", false, "NoManualOverride", "No manual override present")
    |> set_default_condition("Error", false, "NoError", "No error present")
  end

  defp set_naptime_assigns(%Bonny.Axn{resource: resource} = axn) do
    sleep_time = resource["spec"]["sleepTime"]
    wake_time = resource["spec"]["wakeTime"]
    timezone = resource["spec"]["timezone"]
    %{axn | assigns: Map.put(axn.assigns, :naptime, Drowzee.SleepChecker.naptime?(sleep_time, wake_time, timezone))}
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
    |> put_ingress_to_sleep()
    |> scale_down_deployments()
  end

  defp initiate_wake_up(axn) do
    Logger.info("Initiating wake up")
    axn
    |> set_condition("Transitioning", true, "WakingUp", "Waking up")
    |> wake_up_ingress()
    |> scale_up_deployments()
  end

  defp update_hosts(axn) do
    case get_ingress(axn) do
      {:ok, ingress} ->
        update_status(axn, fn status ->
          Map.put(status, "hosts", Drowzee.K8s.Ingress.get_hosts(ingress))
        end)
      {:error, error} ->
        Logger.error("Failed to get ingress: #{inspect(error)}")
        axn
    end
  end

  defp check_sleep_transition(axn, opts) do
    Logger.info("Checking sleep transition...")
    # TODO: This is a very lazy and non-effective way to confirm the deployments have scaled up
    # TODO: Iterate through the deployments and confirm the pods are running
    manual_override = Keyword.get(opts, :manual_override, false)
    case get_ingress(axn) do
      {:ok, ingress} ->
        if Drowzee.Ingress.redirect_annotation?(ingress) do
          sleep_reason = if manual_override, do: "ManualSleep", else: "ScheduledSleep"
          axn
          |> set_condition("Transitioning", false, "NoTransition", "No transition in progress")
          |> set_condition("Sleeping", true, sleep_reason, "Deployments have been scaled down and ingress updated.")
        else
          Logger.debug("Ingress not yet asleep. Transition still in progress...")
          axn |> initiate_sleep()
        end
      {:error, error} ->
        Logger.error("Error checking sleep transition: #{inspect(error)}")
        axn
    end
  end

  defp check_wake_up_transition(axn, opts) do
    Logger.info("Checking wake up transition...")
    # TODO: This is a very lazy and non-effective way to confirm the deployments have scaled down
    # TODO: Iterate through the deployments and confirm the pods are running
    manual_override = Keyword.get(opts, :manual_override, false)
    case get_ingress(axn) do
      {:ok, ingress} ->
        unless Drowzee.Ingress.redirect_annotation?(ingress) do
          wake_reason = if manual_override, do: "ManualWakeUp", else: "ScheduledWakeUp"
          axn
          |> set_condition("Transitioning", false, "NoTransition", "No transition in progress")
          |> set_condition("Sleeping", false, wake_reason, "Deployments have been scaled up and ingress restored.")
        else
          axn |> initiate_wake_up()
        end
      {:error, error} ->
        Logger.error("Failed to check wake up transition: #{inspect(error)}")
        axn
    end
  end

  defp scale_down_deployments(%Bonny.Axn{resource: resource} = axn) do
    Logger.debug("Scaling down deployments...")
    Enum.map(resource["spec"]["deployments"], &scale_deployment(axn, &1, 0))
    axn
  end

  defp scale_up_deployments(%Bonny.Axn{resource: resource} =axn) do
    Logger.debug("Scaling up deployments...")
    Enum.map(resource["spec"]["deployments"], &scale_deployment(axn, &1, 1))
    axn
  end

  defp scale_deployment(%Bonny.Axn{} = axn, deployment, replicas) do
    Logger.info("Scaling deployment", deployment: deployment["name"], replicas: replicas)
    case get_deployment(axn, deployment["name"]) do
      {:ok, deployment} ->
        deployment = put_in(deployment["spec"]["replicas"], replicas)
        case K8s.Client.run(axn.conn, K8s.Client.update(deployment)) do
          {:ok, deployment} -> {:ok, deployment}
          {:error, reason} ->
            Logger.error("Failed to scale deployment: #{inspect(reason)}", deployment: deployment["name"], replicas: replicas)
            {:error, reason}
        end
      {:error, reason} ->
        Logger.error("Failed to find deployment: #{inspect(reason)}", deployment: deployment["name"])
        {:error, reason}
    end
  end

  defp get_ingress(%Bonny.Axn{resource: resource, conn: conn}) do
    ingress_name = resource["spec"]["ingressName"]
    namespace = resource["metadata"]["namespace"]
    Logger.debug("Fetching ingress", ingress_name: ingress_name)
    K8s.Client.get("networking.k8s.io/v1", :ingress, name: ingress_name, namespace: namespace)
    |> K8s.Client.put_conn(conn)
    |> K8s.Client.run()
  end

  defp get_deployment(%Bonny.Axn{resource: resource, conn: conn}, name) do
    namespace = resource["metadata"]["namespace"]
    Logger.debug("Fetching deployment", deployment_name: name)
    K8s.Client.get("apps/v1", :deployment, name: name, namespace: namespace)
    |> K8s.Client.put_conn(conn)
    |> K8s.Client.run()
  end

  defp get_drowzee_ingress(%Bonny.Axn{conn: conn}) do
    name = "drowzee"
    namespace = Drowzee.K8s.drowzee_namespace()
    Logger.debug("Fetching drowzee ingress", ingress_name: name, drowzee_namespace: namespace)
    K8s.Client.get("networking.k8s.io/v1", :ingress, name: name, namespace: namespace)
    |> K8s.Client.put_conn(conn)
    |> K8s.Client.run()
  end

  defp put_ingress_to_sleep(axn) do
    with {:ok, ingress} <- get_ingress(axn),
        {:ok, drowzee_ingress} <- get_drowzee_ingress(axn),
        {:ok, updated_ingress} <- Drowzee.Ingress.add_redirect_annotation(ingress, axn.resource, drowzee_ingress),
        {:ok, _} <- K8s.Client.run(axn.conn, K8s.Client.update(updated_ingress)) do
      Logger.info("Updated ingress to redirect to Drowzee", ingress_name: ingress["metadata"]["name"])
      # register_event(axn, nil, :Normal, "SleepingIngress", "Ingress has been put to sleep")
      axn
    else
      {:error, error} ->
        Logger.error("Failed to redirect ingress to Drowzee: #{inspect(error)}", ingress_name: axn.resource["spec"]["ingressName"])
        axn
    end
  end

  defp wake_up_ingress(axn) do
    with {:ok, ingress} <- get_ingress(axn),
         {:ok, updated_ingress} <- Drowzee.Ingress.remove_redirect_annotation(ingress) do
      case K8s.Client.run(axn.conn, K8s.Client.update(updated_ingress)) do
        {:ok, _} ->
          Logger.info("Removed Drowzee redirect from ingress", ingress_name: ingress["metadata"]["name"])
          # register_event(axn, nil, :Normal, "WakeUpIngress", "Ingress has been restored")
          axn
        {:error, error} ->
          Logger.error("Failed to remove Drowzee redirect from ingress: #{inspect(error)}", ingress_name: ingress["metadata"]["name"])
          axn
      end
    else
      {:error, error} ->
        Logger.error("Failed to restore original ingress state: #{inspect(error)}", ingress_name: axn.resource["spec"]["ingressName"])
        axn
    end
  end
end
