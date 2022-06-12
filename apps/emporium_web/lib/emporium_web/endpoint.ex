defmodule EmporiumWeb.Endpoint do
  @otp_app Mix.Project.config()[:app]
  use Phoenix.Endpoint, otp_app: @otp_app

  @session_options [
    store: :cookie,
    key: "_emporium_web_key",
    signing_salt: "sRR3qZA6"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :emporium_web,
    gzip: false,
    only: ~w(assets favicon.ico robots.txt)

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug EmporiumWeb.Router

  def init(_, config) do
    EmporiumEnvironment.Endpoint.init(config)
  end
end
