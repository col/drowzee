defmodule Drowzee.Config do
  @moduledoc """
  Manages Drowzee configuration
  """

  def namespaces() do
    namespace = Bonny.Config.namespace()

    if is_atom(namespace) do
      # Handle the atom case - keep :all as is
      [namespace]
    else
      # Handle the string case
      if namespace == "__ALL__" do
        [:all]
      else
        namespace
        |> String.split(",")
        |> Enum.map(&String.trim/1)
      end
    end
  end

  def has_cluster_role?() do
    namespace = Bonny.Config.namespace()
    # Convert namespace to atom if it's a binary string to allow comparison with :all
    # This ensures binary() == :all doesn't happen directly
    is_atom(namespace) and namespace == :all or
      namespace == "__ALL__" or
      namespaces() |> Enum.count() > 1
  end
end
