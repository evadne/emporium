defmodule EmporiumWeb.Presence do
  use Phoenix.Presence, otp_app: :emporium_web, pubsub_server: EmporiumWeb.PubSub
end
