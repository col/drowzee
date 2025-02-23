defmodule Drowzee.K8s.Condition do
  def new(type, status, reason \\ nil, message \\ nil) do
    %{
      "type" => type,
      "status" => if(status, do: "True", else: "False"),
      "message" => message,
      "reason" => reason,
      "lastHeartbeatTime" => DateTime.utc_now(),
      "lastTransitionTime" => DateTime.utc_now()
    }
  end
end
