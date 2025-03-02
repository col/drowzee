defmodule DrowzeeWeb.HomeLive.Index do
  use DrowzeeWeb, :live_view

  require Logger
  import Drowzee.K8s.SleepSchedule

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Drowzee.PubSub, "sleep_schedule:updates")

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
      |> assign(:name, nil)
      |> load_sleep_schedules()

    {:noreply, socket}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    socket = socket
      |> assign(:page_title, "All Namespaces")
      |> assign(:namespace, nil)
      |> assign(:name, nil)
      |> load_sleep_schedules()

    {:noreply, socket}
  end

  @impl true
  def handle_event("wake_schedule", %{"name" => name, "namespace" => namespace}, socket) do
    sleep_schedule = Drowzee.K8s.get_sleep_schedule!(name, namespace)

    socket = case Drowzee.K8s.manual_wake_up(sleep_schedule) do
      {:ok, _sleep_schedule} ->
        load_sleep_schedules(socket)
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
      {:ok, _sleep_schedule} ->
        load_sleep_schedules(socket)
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
      {:ok, _sleep_schedule} ->
        load_sleep_schedules(socket)
      {:error, error} ->
        socket
        |> load_sleep_schedules()
        |> put_flash(:error, "Failed to sleep #{name}: #{inspect(error)}")
    end

    {:noreply, socket}
  end

  @impl true
  @spec handle_info({:sleep_schedule_updated}, map()) :: {:noreply, map()}
  def handle_info({:sleep_schedule_updated}, socket) do
    Logger.debug("LiveView: Received sleep schedule update")
    {:noreply, load_sleep_schedules(socket)}
  end

  defp load_sleep_schedules(socket) do
    sleep_schedules = if socket.assigns.name == nil do
      Drowzee.K8s.sleep_schedules(socket.assigns.namespace)
    else
      [Drowzee.K8s.get_sleep_schedule!(socket.assigns.name, socket.assigns.namespace)]
    end

    sleep_schedules = Enum.map(sleep_schedules, fn sleep_schedule ->
      host = case Drowzee.K8s.SleepSchedule.get_ingress(sleep_schedule) do
        {:ok, ingress} -> Drowzee.K8s.Ingress.get_hosts(ingress) |> List.first()
        {:error, _error} -> nil
      end
      Map.put(sleep_schedule, "host", host)
    end)
    assign(socket, :sleep_schedules, sleep_schedules)
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
end
