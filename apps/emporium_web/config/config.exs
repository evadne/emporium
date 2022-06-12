import Config

config :emporium_web, generators: [context_app: :emporium]

config :emporium_web, EmporiumWeb.Endpoint,
  render_errors: [view: EmporiumWeb.ErrorView, accepts: ~w(html json)],
  pubsub_server: EmporiumWeb.PubSub

import_config "#{config_env()}.exs"
