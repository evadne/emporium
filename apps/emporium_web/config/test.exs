import Config

config :emporium_web, EmporiumWeb.Endpoint,
  http: [port: {:system, "URL_PORT", 4010}],
  secret_key_base: :base64.encode(:crypto.strong_rand_bytes(128)),
  live_view: [signing_salt: :base64.encode(:crypto.strong_rand_bytes(128))]
