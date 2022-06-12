defmodule EmporiumEnviornment.Cluster.Strategy.Local do
  @moduledoc """
  EPMD-based Clustering strategy for libCluster, which uses net_adm to
  find out which names have been registered with the local EPMD instance,
  and then sending them to libCluster for connection.

  This allows forming the cluster with all locally running nodes,
  and is especially useful during development when ./bin/run and
  ./bin/console scripts already take care of starting the BEAM VM up
  with clustering.
  """

  use Cluster.Strategy
  alias Cluster.Strategy.State
  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def init([%State{topology: topology, connect: connect, list_nodes: list_nodes}]) do
    {:ok, epmd_names} = :net_adm.names()
    epmd_nodes = Enum.map(epmd_names, &String.to_atom("#{elem(&1, 0)}@localhost"))
    :ok = Cluster.Strategy.connect_nodes(topology, connect, list_nodes, epmd_nodes)
    :ignore
  end
end
