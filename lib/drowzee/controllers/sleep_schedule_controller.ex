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
    # - Clean up ingress backups
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

  # Backup ingress
  # - get existing ingress backup
  # - if not,
  #   - create a new backup
  #   - fail if not found or ingress is already a drowzee ingress
  # - if exists,
  #   - update the backup (provided it's not already a drowzee ingress)
  # - update the 'ingressBackup' condition
  defp backup_ingress(%Bonny.Axn{} = axn) do
    unless Drowzee.K8s.SleepSchedule.is_sleeping?(axn.resource) do
      case get_ingress_backup_configmap(axn) do
        {:ok, configmap} -> backup_ingress(axn, configmap)
        {:error, %K8s.Client.APIError{reason: "NotFound"}} -> backup_ingress(axn, nil)
        {:error, error} ->
          Logger.error("Error fetching ingress backup configmap: #{inspect(error)}")
          axn
      end
    else
      axn
    end
  end

  defp backup_ingress(%Bonny.Axn{} = axn, nil) do
    with {:ok, ingress} <- get_ingress(axn),
         :ok <- check_original_ingress(ingress),
         {:ok, _configmap} <- create_ingress_backup(axn, ingress) do
      set_condition(axn, "IngressBackup", true, "Backup", "Original ingress backed up")
    else
      {:error, error} ->
        Logger.error("Error backing up ingress: #{inspect(error)}")
        axn
    end
  end

  defp backup_ingress(%Bonny.Axn{} = axn, configmap) do
    case get_ingress(axn) do
      {:ok, ingress} ->
        with :ok <- check_original_ingress(ingress),
            {:ok, _configmap} <- update_ingress_backup_configmap(axn, configmap, ingress) do
          set_condition(axn, "IngressBackup", true, "Backup", "Original ingress backed up")
        else
          {:error, %K8s.Client.APIError{} = error} ->
            Logger.warning("Failed to update ingress backup: #{error.message}")
            # continue with existing backup
            axn
          {:error, error} ->
            Logger.warning("Failed to update ingress backup: #{inspect(error)}")
            axn
        end
      {:error, error} ->
        Logger.error("Failed to load ingress: #{inspect(error)}", ingress_name: axn.resource["spec"]["ingressName"])
        axn
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
    |> backup_ingress()
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

  defp check_sleep_transition(axn, opts) do
    Logger.info("Checking sleep transition...")
    # TODO: This is a very lazy and non-effective way to confirm the deployments have scaled up
    # TODO: Iterate through the deployments and confirm the pods are running
    manual_override = Keyword.get(opts, :manual_override, false)
    case get_ingress(axn) do
      {:ok, ingress} ->
        if Drowzee.Ingress.sleeping_annotation?(ingress) do
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
        unless Drowzee.Ingress.sleeping_annotation?(ingress) do
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

  defp create_ingress_backup(%Bonny.Axn{resource: resource, conn: conn}, ingress) do
    configmap_name = "#{resource["spec"]["ingressName"]}-drowzee-backup"
    namespace = resource["metadata"]["namespace"]
    Logger.debug("Creating ingress backup", configmap_name: configmap_name)
    configmap = Drowzee.ConfigMap.create_configmap(configmap_name, namespace, ingress)
    K8s.Client.create(configmap)
    |> K8s.Client.put_conn(conn)
    |> K8s.Client.run()
  end

  defp update_ingress_backup_configmap(%Bonny.Axn{resource: resource, conn: conn}, configmap, ingress) do
    if Drowzee.ConfigMap.update_required?(configmap, ingress) do
      configmap_name = "#{resource["spec"]["ingressName"]}-drowzee-backup"
      namespace = resource["metadata"]["namespace"]
      Logger.debug("Updating ingress backup", configmap_name: configmap_name)
      Drowzee.ConfigMap.create_configmap(configmap_name, namespace, ingress)
      |> K8s.Client.update(configmap)
      |> K8s.Client.put_conn(conn)
      |> K8s.Client.run()
    else
      {:ok, configmap}
    end
  end

  defp get_ingress_backup_configmap(%Bonny.Axn{resource: resource, conn: conn}) do
    configmap_name = "#{resource["spec"]["ingressName"]}-drowzee-backup"
    namespace = resource["metadata"]["namespace"]
    Logger.debug("Fetching ingress backup configmap", configmap_name: configmap_name)
    K8s.Client.get("v1", :configmap, name: configmap_name, namespace: namespace)
    |> K8s.Client.put_conn(conn)
    |> K8s.Client.run()
  end

  defp get_ingress_backup(%Bonny.Axn{} = axn) do
    with {:ok, configmap} <- get_ingress_backup_configmap(axn),
         {:ok, json} <- Jason.decode(configmap["data"]["ingress.json"]) do
      {:ok, json}
    else
      {:error, error} ->
        Logger.error("Failed to load ingress backup: #{inspect(error)}")
        {:error, error}
    end
  end

  defp get_drowzee_service(%Bonny.Axn{conn: conn}) do
    name = "drowzee"
    namespace = Drowzee.K8s.drowzee_namespace()
    Logger.debug("Fetching drowzee service", service_name: name, drowzee_namespace: namespace)
    K8s.Client.get("v1", :service, name: name, namespace: namespace)
    |> K8s.Client.put_conn(conn)
    |> K8s.Client.run()
  end

  defp put_ingress_to_sleep(axn) do
    with {:ok, ingress} <- get_ingress(axn),
        {:ok, service} <- get_drowzee_service(axn),
        {:ok, updated_ingress} <- Drowzee.Ingress.update_for_service(ingress, service),
        {:ok, updated_ingress} <- Drowzee.Ingress.add_sleeping_annotation(updated_ingress),
        {:ok, _} <- K8s.Client.run(axn.conn, K8s.Client.update(updated_ingress)) do
      Logger.info("Updated ingress to redirect to drowzee service", ingress_name: ingress["metadata"]["name"])
      # register_event(axn, nil, :Normal, "SleepingIngress", "Ingress has been put to sleep")
      axn
    else
      {:error, error} ->
        Logger.error("Failed to put ingress to sleep: #{inspect(error)}", ingress_name: axn.resource["spec"]["ingressName"])
        axn
    end
  end

  defp wake_up_ingress(axn) do
    with {:ok, ingress} <- get_ingress(axn),
        {:ok, ingress_backup} <- get_ingress_backup(axn) do
      ingress = %{ingress | "spec" => ingress_backup["spec"]}
      {:ok, ingress} = Drowzee.Ingress.remove_sleeping_annotation(ingress)
      case K8s.Client.run(axn.conn, K8s.Client.update(ingress)) do
        {:ok, _} ->
          Logger.info("Updated ingress to original state", ingress_name: ingress["metadata"]["name"])
          # register_event(axn, nil, :Normal, "WakeUpIngress", "Ingress has been restored")
          axn
        {:error, error} ->
          Logger.error("Failed to restore original ingress state: #{inspect(error)}", ingress_name: ingress["metadata"]["name"])
          axn
      end
    else
      {:error, error} ->
        Logger.error("Failed to restore original ingress state: #{inspect(error)}", ingress_name: axn.resource["spec"]["ingressName"])
        axn
    end
  end

  defp check_original_ingress(ingress) do
    if Drowzee.Ingress.sleeping_annotation?(ingress) do
      {:error, "Cannot backup sleeping ingress"}
    else
      :ok
    end
  end
end
