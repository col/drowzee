defmodule DrowzeeWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use DrowzeeWeb, :html

  embed_templates "page_html/*"

  def get_condition(sleep_schedule, type) do
    sleep_schedule["status"]["conditions"]
    |> Enum.filter(&(&1["type"] == type))
    |> List.first() || %{}
  end

  def condition_class(sleep_schedule, type) do
    if get_condition(sleep_schedule, type)["status"] == "True" do
      "text-green-600"
    else
      "text-red-600"
    end
  end
end
