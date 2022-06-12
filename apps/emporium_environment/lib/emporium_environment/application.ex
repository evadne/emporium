defmodule EmporiumEnvironment.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      EmporiumEnvironment.Horde.Tracker,
      EmporiumEnvironment.Cluster.Supervisor
    ]

    opts = [strategy: :one_for_one, name: EmporiumEnvironment.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
