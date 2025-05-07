defmodule DrowzeeWeb.HomeLive.Index do
  use DrowzeeWeb, :live_view

  require Logger
  import Drowzee.K8s.SleepSchedule

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Drowzee.PubSub, "sleep_schedule:updates")

    socket = socket
      |> assign(:search, "")
      |> assign(:filtered_sleep_schedules, nil)
      |> assign(:namespace, nil)
      |> assign(:name, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"namespace" => namespace, "name" => name}, _url, socket) do
    socket = socket
      |> assign(:page_title, "#{namespace} / #{name}")
      |> assign(:namespace, namespace)
      |> assign(:name, name)
      |> load_sleep_schedules()

    {:noreply, socket}
  end

  @impl true
  def handle_params(%{"namespace" => namespace}, _url, socket) do
    socket = socket
      |> assign(:page_title, "#{namespace}")
      |> assign(:namespace, namespace)
      |> load_sleep_schedules()

    {:noreply, socket}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    socket = socket
      |> assign(:page_title, "All Namespaces")
      |> load_sleep_schedules()

    {:noreply, socket}
  end

  @impl true
  def handle_event("wake_schedule", %{"name" => name, "namespace" => namespace}, socket) do
    sleep_schedule = Drowzee.K8s.get_sleep_schedule!(name, namespace)

    socket = case Drowzee.K8s.manual_wake_up(sleep_schedule) do
      {:ok, sleep_schedule} ->
        # Note: Bit of a hack to make the UI update immediately rather than waiting for the controller to handle the ManualOverride action
        sleep_schedule = Drowzee.K8s.SleepSchedule.put_condition(sleep_schedule, "Transitioning", "True", "WakingUp", "Waking up")
        replace_sleep_schedule(socket, sleep_schedule)
      {:error, error} ->
        socket
        |> load_sleep_schedules()
        |> put_flash(:error, "Failed to wake up #{name}: #{inspect(error)}")
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("sleep_schedule", %{"name" => name, "namespace" => namespace}, socket) do
    sleep_schedule = Drowzee.K8s.get_sleep_schedule!(name, namespace)

    socket = case Drowzee.K8s.manual_sleep(sleep_schedule) do
      {:ok, sleep_schedule} ->
        # Note: Bit of a hack to make the UI update immediately rather than waiting for the controller to handle the ManualOverride action
        sleep_schedule = Drowzee.K8s.SleepSchedule.put_condition(sleep_schedule, "Transitioning", "True", "Sleeping", "Going to sleep")
        replace_sleep_schedule(socket, sleep_schedule)
      {:error, error} ->
        socket
        |> load_sleep_schedules()
        |> put_flash(:error, "Failed to sleep #{name}: #{inspect(error)}")
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("remove_override", %{"name" => name, "namespace" => namespace}, socket) do
    sleep_schedule = Drowzee.K8s.get_sleep_schedule!(name, namespace)

    socket = case Drowzee.K8s.remove_override(sleep_schedule) do
      {:ok, sleep_schedule} ->
        replace_sleep_schedule(socket, sleep_schedule)
      {:error, error} ->
        socket
        |> load_sleep_schedules()
        |> put_flash(:error, "Failed to sleep #{name}: #{inspect(error)}")
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("sleep_all_schedules", %{"namespace" => namespace}, socket) when is_binary(namespace) do
    sleep_schedules = Drowzee.K8s.sleep_schedules(namespace)

    results = Enum.map(sleep_schedules, fn sleep_schedule ->
      Drowzee.K8s.manual_sleep(sleep_schedule)
    end)

    # Wait a second before reloading all the schedules
    Process.sleep(1000)
    socket = load_sleep_schedules(socket)

    has_error = Enum.any?(results, fn {:error, _error} -> true; _ -> false end)
    socket = if has_error, do: put_flash(socket, :error, "Failed to sleep at least one schedule"), else: socket

    {:noreply, socket}
  end

  @impl true
  def handle_event("wake_all_schedules", %{"namespace" => namespace}, socket) when is_binary(namespace) do
    sleep_schedules = Drowzee.K8s.sleep_schedules(namespace)

    results = Enum.map(sleep_schedules, fn sleep_schedule ->
      Drowzee.K8s.manual_wake_up(sleep_schedule)
    end)

    # Wait a second before reloading all the schedules
    Process.sleep(1000)
    socket = load_sleep_schedules(socket)

    has_error = Enum.any?(results, fn {:error, _error} -> true; _ -> false end)
    socket = if has_error, do: put_flash(socket, :error, "Failed to wake up at least one schedule"), else: socket

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    socket = socket
      |> assign(:search, search)
      |> filter_sleep_schedules(search)
    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_search", _, socket) do
    socket = socket
      |> assign(:search, "")
      |> assign(:filtered_sleep_schedules, nil)
    {:noreply, socket}
  end

  defp filter_sleep_schedules(socket, nil) do
    assign(socket, :filtered_sleep_schedules, nil)
  end

  defp filter_sleep_schedules(socket, "") do
    assign(socket, :filtered_sleep_schedules, nil)
  end

  defp filter_sleep_schedules(socket, search) do
    search = String.downcase(search)
    filtered_sleep_schedules = Enum.filter(socket.assigns.sleep_schedules, fn sleep_schedule ->
      String.contains?(sleep_schedule["metadata"]["name"], search) ||
      String.contains?(sleep_schedule["metadata"]["namespace"], search)
    end)

    assign(socket, :filtered_sleep_schedules, filtered_sleep_schedules)
  end

  @impl true
  @spec handle_info({:sleep_schedule_updated}, map()) :: {:noreply, map()}
  def handle_info({:sleep_schedule_updated}, socket) do
    Logger.debug("LiveView: Received sleep schedule update")
    {:noreply, load_sleep_schedules(socket)}
  end

  defp load_sleep_schedules(socket) do
    sleep_schedules = case socket.assigns.name do
      nil ->
        Drowzee.K8s.sleep_schedules(socket.assigns.namespace)
      name ->
        [Drowzee.K8s.get_sleep_schedule!(name, socket.assigns.namespace)]
    end

    # Gather all deployments for all schedules
    deployments =
      sleep_schedules
      |> Enum.flat_map(fn schedule ->
        case Drowzee.K8s.SleepSchedule.get_deployments(schedule) do
          {:ok, ds} -> ds
          {:error, _} -> []
        end
      end)

    statefulsets =
      sleep_schedules
      |> Enum.flat_map(fn schedule ->
        case Drowzee.K8s.SleepSchedule.get_statefulsets(schedule) do
          {:ok, ss} -> ss
          {:error, _} -> []
        end
      end)

    cronjobs =
      sleep_schedules
      |> Enum.flat_map(fn schedule ->
        case Drowzee.K8s.SleepSchedule.get_cronjobs(schedule) do
          {:ok, cs} -> cs
          {:error, _} -> []
        end
      end)

    deployments_by_name = Map.new(deployments, &{&1["metadata"]["name"], &1})
    statefulsets_by_name = Map.new(statefulsets, &{&1["metadata"]["name"], &1})
    cronjobs_by_name = Map.new(cronjobs, &{&1["metadata"]["name"], &1})

    socket
    |> assign(:sleep_schedules, sleep_schedules)
    |> assign(:deployments_by_name, deployments_by_name)
    |> assign(:statefulsets_by_name, statefulsets_by_name)
    |> assign(:cronjobs_by_name, cronjobs_by_name)
    |> filter_sleep_schedules(socket.assigns.search)
  end

  def sleep_schedule_host(sleep_schedule) do
    (sleep_schedule["status"]["hosts"] || []) |> List.first()
  end

  def condition_class(sleep_schedule, type) do
    if get_condition(sleep_schedule, type)["status"] == "True" do
      "text-green-600"
    else
      "text-red-600"
    end
  end

  def last_transaction_time(sleep_schedule, type) do
    get_condition(sleep_schedule, type)["lastTransitionTime"]
      |> Timex.parse!("{ISO:Extended}")
      |> Timex.to_datetime(sleep_schedule["spec"]["timezone"])
      |> Timex.format!("{h12}:{m}{am}")
  end

  def replace_sleep_schedule(socket, updated_sleep_schedule) do
    sleep_schedules = Enum.map(socket.assigns.sleep_schedules, fn sleep_schedule ->
      if sleep_schedule["metadata"]["name"] == updated_sleep_schedule["metadata"]["name"] && sleep_schedule["metadata"]["namespace"] == updated_sleep_schedule["metadata"]["namespace"] do
        updated_sleep_schedule
      else
        sleep_schedule
      end
    end)
    assign(socket, :sleep_schedules, sleep_schedules)
  end
end
