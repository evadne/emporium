import Config

config :emporium_web, EmporiumWeb.Endpoint,
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: [
    node: ["esbuild.js", "--watch", cd: Path.expand("../assets", __DIR__)]
  ],
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/emporium_web/(live|views)/.*(ex)$",
      ~r"lib/emporium_web/templates/.*(eex)$"
    ]
  ]
