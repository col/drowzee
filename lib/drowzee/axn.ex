defmodule Drowzee.Axn do

  @doc """
  Gets the condition in the resource status by type name.
  """
  # @spec set_condition(
  #   axn :: t(),
  #   type :: binary()
  # ) :: t()
  def get_condition(axn, type) do
    conditions = get_in(axn.resource, ["status", "conditions"]) || []
    case Enum.filter(conditions, fn cond -> cond["type"] == type end) do
      [] -> {:error, :not_found}
      [condition] -> {:ok, condition}
      [_|_] -> {:error, :multiple}
    end
  end

  @doc """
  Sets the condition in the resource status.

  The field `.status.conditions`, if configured in the CRD, nolds a list of
  conditions, their `status` with a `message`, an optional `reason`, and two
  timestamps.
  """
  # @spec set_condition(
  #   axn :: t(),
  #   type :: binary(),
  #   status :: boolean(),
  #   reason :: binary() | nil,
  #   message :: binary() | nil
  # ) :: t()
  def set_condition(axn, type, status, reason \\ nil, message \\ nil) do
    condition_status = if(status, do: "True", else: "False")
    now = DateTime.utc_now()

    condition =
    %{
      "type" => type,
      "status" => condition_status,
      "message" => message,
      "reason" => reason,
      "lastHeartbeatTime" => now,
      "lastTransitionTime" => now
    }
    |> Map.reject(&is_nil(elem(&1, 1)))

    Bonny.Axn.update_status(axn, fn status ->
      next_conditions =
        status
        |> Map.get("conditions", [])
        |> Map.new(&{&1["type"], &1})
        |> Map.update(type, condition, fn
          %{"status" => ^condition_status} = old_condition ->
            Map.put(condition, "lastTransitionTime", old_condition["lastTransitionTime"])

          _old_condition ->
            condition
        end)
        |> Map.values()

      Map.put(status, "conditions", next_conditions)
    end)
  end

  # @spec set_default_condition(
  #   axn :: t(),
  #   type :: binary(),
  #   status :: boolean(),
  #   reason :: binary() | nil,
  #   message :: binary() | nil
  # ) :: t()
  def set_default_condition(axn, type, value, reason, message) do
    case get_condition(axn, type) do
      {:ok, _condition} -> axn
      {:error, :not_found} ->
        set_condition(axn, type, value, reason, message)
      {:error, :multiple} -> axn
    end
  end
end
