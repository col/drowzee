defmodule Drowzee.Config do
  @moduledoc """
  Manages Drowzee configuration
  """

  def namespaces() do
    Bonny.Config.namespace()
    |> String.split(",")
    |> Enum.map(&String.trim/1)
  end

  def has_cluster_role?() do
    Bonny.Config.namespace() == "__ALL__" or namespaces() |> Enum.count() > 1
  end
end
