import Config

for config <- "../apps/*/config/config.exs" |> Path.expand(__DIR__) |> Path.wildcard() do
  import_config config
end

if config_env() != :test do
  routes = [
    emporium_web: {EmporiumWeb.Endpoint, "/"}
  ]

  config :emporium_proxy, EmporiumProxy,
    applications: Enum.uniq(Enum.map(routes, &elem(&1, 0))),
    endpoints: Enum.map(routes, &elem(&1, 1))

  for {app, {endpoint, mount}} <- routes do
    config(app, endpoint, url: [path: mount])
  end
end

config :logger,
  compile_time_purge_matching: [
    [level_lower_than: :info],
    [module: Membrane.SRTP.Encryptor, function: "handle_event/4", level_lower_than: :error]
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:application, :request_id]

config :phoenix, :json_library, Jason

config :nx, default_backend: EXLA.Backend

import_config "#{config_env()}.exs"
