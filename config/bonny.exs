
import Config

config :bonny,

  # Function to call to get a K8s.Conn object.
  # The function should return a %K8s.Conn{} struct or a {:ok, %K8s.Conn{}} tuple
  get_conn: {Drowzee.K8sConn, :get!, [config_env()]},

  # Name must only consist of only lowercase letters and hyphens.
  # Defaults to hyphenated mix app name
  service_account_name: "drowzee",

  # Labels to apply to the operator's resources.
  labels: %{
    "k8s-app" => "drowzee"
  },

  # Operator deployment resources. These are the defaults.
  resources: %{requests: %{cpu: "200m", memory: "200Mi"}, limits: %{cpu: "200m", memory: "200Mi"}},

  manifest_override_callback: &Mix.Tasks.Bonny.Gen.Manifest.DrowzeeCustomizer.override/1
