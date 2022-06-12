import Config

config :emporium_environment, EmporiumEnvironment, strategies: []

config :opentelemetry, :resource,
  service: [
    name: "emporium",
    namespace: "emporium"
  ]

config :opentelemetry,
  processors: [
    otel_batch_processor: %{
      exporter: {:otel_exporter_stdout, []}
    }
  ]

# config :opentelemetry, traces_exporter: :none

import_config "#{config_env()}.exs"
