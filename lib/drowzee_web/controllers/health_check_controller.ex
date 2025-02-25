defmodule DrowzeeWeb.HealthCheckController do
  use DrowzeeWeb, :controller

  def health_check(conn, _params) do
    text(conn, "OK")
  end
end
