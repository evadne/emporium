defmodule EmporiumWeb.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: EmporiumWeb.PubSub},
      EmporiumWeb.Presence,
      EmporiumWeb.Telemetry,
      EmporiumWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: EmporiumWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    EmporiumWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
