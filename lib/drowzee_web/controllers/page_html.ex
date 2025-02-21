defmodule DrowzeeWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use DrowzeeWeb, :html

  embed_templates "page_html/*"

  def naptime_condition(sleep_schedule) do
    sleep_schedule["status"]["conditions"]
    |> Enum.filter(&(&1["type"] == "naptime"))
    |> List.first()
  end

  def naptime_class(sleep_schedule) do
    if naptime_condition(sleep_schedule)["status"] == "True" do
      "text-green-600"
    else
      "text-red-600"
    end
  end
end
