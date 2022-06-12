defmodule EmporiumNexus.Application do
  use Application

  def start(_type, _args) do
    children = [
      EmporiumNexus.KeyServer
    ]

    opts = [strategy: :one_for_one, name: EmporiumNexus.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
