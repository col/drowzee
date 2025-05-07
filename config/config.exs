# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :drowzee,
  generators: [timestamp_type: :utc_datetime]

config :drowzee, Drowzee.K8sConn, method: :kube_config

# Configures the endpoint
config :drowzee, DrowzeeWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DrowzeeWeb.ErrorHTML, json: DrowzeeWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Drowzee.PubSub,
  live_view: [signing_salt: "cc5cRuN6"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  drowzee: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  drowzee: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time [$level] $message $metadata\n",
  metadata: [:name, :namespace, :deployment, :statefulset, :cronjob, :replicas, :ingress_name, :configmap_name, :schedule_name, :schedule_namespace, :request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

import_config "bonny.exs"
