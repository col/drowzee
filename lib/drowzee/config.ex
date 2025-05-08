defmodule Drowzee.Config do
  @moduledoc """
  Manages Drowzee configuration
  """

  def namespaces() do
    namespace = Bonny.Config.namespace()
    
    case namespace do
      "__ALL__" -> ["__ALL__"]
      _ -> 
        namespace
        |> String.split(",")
        |> Enum.map(&String.trim/1)
    end
  end

  def has_cluster_role?() do
    Bonny.Config.namespace() == "__ALL__" or namespaces() |> Enum.count() > 1
  end
end
