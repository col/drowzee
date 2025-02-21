defmodule DrowzeeWeb.PageController do
  use DrowzeeWeb, :controller

  def home(conn, _params) do
    operation = K8s.Client.list("drowzee.challengr.io/v1beta1", "SleepSchedule", namespace: "default")
    {:ok, list} = K8s.Client.run(Drowzee.K8sConn.get!(Mix.env()), operation)
    conn = assign(conn, :sleep_schedules, list["items"])

    render(conn, :home, layout: false)
  end
end
