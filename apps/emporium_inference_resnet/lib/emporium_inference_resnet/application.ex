defmodule EmporiumInference.ResNet.Application do
  use Application

  def start(_type, _args) do
    children = [
      EmporiumInference.ResNet.Serving
    ]

    options = [strategy: :one_for_one, name: EmporiumInference.ResNet.Supervisor]
    Supervisor.start_link(children, options)
  end
end
