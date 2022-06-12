defmodule EmporiumEnvironment.Horde.Client do
  @moduledoc """
  The Horde Client lives in Supervision trees elsewhere (for example under
  EmporiumAccess.Supervisor), and is responsible for joining Hordes managed
  by that Supervision tree with Hordes running on remote nodes.
  """

  use GenServer
  require Logger

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{target: module()}
    defstruct target: nil
  end

  def start_link(options) do
    {_, name} = List.keyfind(options, :name, 0)
    {_, target} = List.keyfind(options, :target, 0)
    GenServer.start_link(__MODULE__, target, name: name)
  end

  def init(target) do
    :ok = GenServer.call(EmporiumEnvironment.Horde.Tracker, {:add_subscriber, self()})
    _ = join_hordes(target, Node.list())
    {:ok, %State{target: target}}
  end

  def handle_cast({:nodes_updated, node_names}, state) do
    _ = join_hordes(state.target, node_names)
    {:noreply, state}
  end

  defp join_hordes(target, node_names) do
    registry_result = target |> Module.concat(Horde.Registry) |> set_members(node_names)
    supervisor_result = target |> Module.concat(Horde.Supervisor) |> set_members(node_names)
    {registry_result, supervisor_result}
  end

  defp set_members(supervisor_name, node_names) do
    remote_members = for node_name <- node_names, do: {supervisor_name, node_name}
    members = [supervisor_name | remote_members]
    result = Horde.Cluster.set_members(supervisor_name, members)
    _ = handle_set_members_result(supervisor_name, node_names, result)
    result
  end

  defp handle_set_members_result(horde_name, node_names, :ok) do
    Logger.info(fn ->
      "set members for #{horde_name} to #{inspect(node_names)}"
    end)
  end

  defp handle_set_members_result(horde_name, node_names, {:error, reason}) do
    Logger.error(fn ->
      "unable to set members for #{horde_name} to #{inspect(node_names)}: #{inspect(reason)})"
    end)
  end
end
