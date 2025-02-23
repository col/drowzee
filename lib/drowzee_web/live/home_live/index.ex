defmodule DrowzeeWeb.HomeLive.Index do
  use DrowzeeWeb, :live_view

  import Drowzee.K8s.SleepSchedule

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Drowzee.PubSub, "sleep_schedule:updates")

    socket =
      socket
      |> assign(:sleep_schedules, Drowzee.K8s.sleep_schedules())

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Home")
    |> assign(:sleep_schedules, Drowzee.K8s.sleep_schedules())
  end

  @impl true
  def handle_event("wake_schedule", %{"name" => name, "namespace" => namespace}, socket) do
    sleep_schedule = Drowzee.K8s.get_sleep_schedule!(name, namespace)

    socket = case Drowzee.K8s.manual_wake_up(sleep_schedule) do
      {:ok, _sleep_schedule} ->
        socket
          |> assign(:sleep_schedules, Drowzee.K8s.sleep_schedules())
          |> put_flash(:info, "Waking up #{name}")
      {:error, error} ->
        socket
          |> assign(:sleep_schedules, Drowzee.K8s.sleep_schedules())
          |> put_flash(:error, "Failed to wake up #{name}: #{inspect(error)}")
    end
    Process.send_after(self(), :clear_flash, 5000)

    {:noreply, socket}
  end

  @impl true
  def handle_event("sleep_schedule", %{"name" => name, "namespace" => namespace}, socket) do
    sleep_schedule = Drowzee.K8s.get_sleep_schedule!(name, namespace)

    socket = case Drowzee.K8s.manual_sleep(sleep_schedule) do
      {:ok, _sleep_schedule} ->
        socket
          |> assign(:sleep_schedules, Drowzee.K8s.sleep_schedules())
          |> put_flash(:info, "Sleeping #{name}")
      {:error, error} ->
        socket
          |> assign(:sleep_schedules, Drowzee.K8s.sleep_schedules())
          |> put_flash(:error, "Failed to sleep #{name}: #{inspect(error)}")
    end
    Process.send_after(self(), :clear_flash, 5000)

    {:noreply, socket}
  end

  @impl true
  def handle_info(:clear_flash, socket) do
    IO.puts "Clearing flash..."
    {:noreply, clear_flash(socket)}
  end

  @impl true
  @spec handle_info({:sleep_schedule_updated}, map()) :: {:noreply, map()}
  def handle_info({:sleep_schedule_updated}, socket) do
    {:noreply, assign(socket, :sleep_schedules, Drowzee.K8s.sleep_schedules())}
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
