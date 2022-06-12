defmodule EmporiumEnvironment.Cluster.Supervisor do
  use Supervisor
  require Logger

  @otp_app Mix.Project.config()[:app]
  @otp_env EmporiumEnvironment

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_) do
    topologies = build_topologies()

    cond do
      Enum.empty?(topologies) -> :ignore
      true -> Cluster.Supervisor.init([topologies, [name: __MODULE__]])
    end
  end

  @strategy_base [
    connect: {__MODULE__, :connect_node, []},
    disconnect: {:erlang, :disconnect_node, []},
    list_nodes: {:erlang, :nodes, [:connected]}
  ]

  defp build_topologies do
    Application.get_env(@otp_app, @otp_env)
    |> Keyword.fetch!(:strategies)
    |> Enum.flat_map(&build_topology/1)
  end

  defp build_topology(:local) do
    strategy = EmporiumEnviornment.Cluster.Strategy.Local
    [local_epmd_discovery: Keyword.merge(@strategy_base, strategy: strategy, config: [])]
  end

  defp build_topology(:fly) do
    with {:ok, app_name} <- System.fetch_env("FLY_APP_NAME") do
      strategy = Cluster.Strategy.DNSPoll
      config = [polling_interval: 5_000, query: "#{app_name}.internal", node_basename: app_name]
      [fly_dnspoll: Keyword.merge(@strategy_base, strategy: strategy, config: config)]
    else
      _ -> []
    end
  end

  def connect_node(node_name) do
    :net_kernel.connect_node(node_name)
  end
end
