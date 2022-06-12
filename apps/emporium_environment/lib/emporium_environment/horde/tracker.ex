defmodule EmporiumEnvironment.Horde.Tracker do
  @moduledoc """
  The Horde Tracker is a resopnsible for messaging all of its subscribers when
  a new node has been added. The subscribers (__MODULE__.Horde.Client) will then
  in turn have their targets join Hordes.
  """

  use GenServer

  defmodule State do
    defstruct subscribers: [], nodes: []
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    :ok = :net_kernel.monitor_nodes(true, node_type: :visible)
    {:ok, %State{}}
  end

  def handle_call({:add_subscriber, pid}, _from, state) when is_pid(pid) do
    monitor_ref = Process.monitor(pid)
    to_subscribers = [{monitor_ref, pid} | state.subscribers]
    to_state = %{state | subscribers: to_subscribers}
    {:reply, :ok, to_state}
  end

  def handle_info({:DOWN, ref, :process, object, _}, state) do
    to_subscribers = state.subscribers |> List.delete({ref, object})
    to_state = %{state | subscribers: to_subscribers}
    {:noreply, to_state}
  end

  def handle_info({:nodeup, node_name, _}, state) do
    to_nodes = [node_name | state.nodes]
    _ = broadcast(state.subscribers, {:nodes_updated, to_nodes})
    {:noreply, %{state | nodes: to_nodes}}
  end

  def handle_info({:nodedown, node_name, _}, state) do
    to_nodes = List.delete(state.nodes, node_name)
    _ = broadcast(state.subscribers, {:nodes_updated, to_nodes})
    {:noreply, %{state | nodes: to_nodes}}
  end

  defp broadcast(subscribers, message) do
    for {_, pid} <- subscribers do
      GenServer.cast(pid, message)
    end
  end
end
