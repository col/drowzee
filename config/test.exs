import Config

# Only required when NOT running in a k8s pod
# This is used to find the drowzee service when updating deployment ingresses
config :drowzee, :drowzee_namespace, "default"

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :drowzee, DrowzeeWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "/HbNJF7xvWX0AXCHFCKZZ1Bp5Jq3LQgZGmAT0RAU2fqfwQ18YxylGVk+Jrp7Rhep",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :drowzee, Drowzee.K8sConn, method: :test
