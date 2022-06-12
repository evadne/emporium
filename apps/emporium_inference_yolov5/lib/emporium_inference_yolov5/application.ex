defmodule EmporiumInference.YOLOv5.Application do
  use Application

  def start(_type, _args) do
    children = [
      EmporiumInference.YOLOv5.Broker,
      EmporiumInference.YOLOv5.Runner
    ]

    options = [strategy: :one_for_one, name: EmporiumInference.YOLOv5.Supervisor]
    Supervisor.start_link(children, options)
  end
end
