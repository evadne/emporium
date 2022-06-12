defmodule EmporiumProxy.Application do
  use Application

  def start(_type, _args) do
    children = build_children()
    opts = [strategy: :one_for_one, name: EmporiumProxy.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp build_children do
    case System.get_env("ROLE") do
      "WEB" -> [EmporiumProxy.Cowboy.build_child_spec()]
      _ -> []
    end
  end
end
