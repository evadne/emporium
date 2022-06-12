defmodule EmporiumInference.YOLOv5.Acceptor do
  @moduledoc """
  The Daemon Acceptor is started by the Daemon Server based on the maximum number of concurrent
  jobs allowed by the underlying daemon (usually 1). The Daemon Acceptor is invoked via the
  Request module, and keeps track of the caller throughput.
  """

  alias EmporiumInference.YOLOv5.Broker

  defmodule State do
    @type t :: %__MODULE__{
            server_pid: nil | pid(),
            client_pid: nil | pid()
          }
    defstruct server_pid: nil,
              client_pid: nil
  end

  def child_spec(server_pid) when is_pid(server_pid) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [server_pid]},
      type: :worker,
      restart: :permanent,
      shutdown: :brutal_kill
    }
  end

  def start_link(server_pid) do
    pid =
      spawn_link(fn ->
        start(server_pid)
      end)

    {:ok, pid}
  end

  def start(server_pid) do
    loop(%State{server_pid: server_pid})
  end

  def loop(%State{client_pid: client_pid} = state) when is_pid(client_pid) do
    _ = Process.unlink(client_pid)
    loop(%{state | client_pid: nil})
  end

  def loop(%State{} = state) do
    with {:go, _ref, client_pid, _relative_time, _sojourn_time} <- :sbroker.ask_r(Broker) do
      true = Process.link(client_pid)
      state = %{state | client_pid: client_pid}
      accept(state)
    else
      {:drop, _sojourn_time} -> :ok
    end
  end

  def accept(%State{} = state) do
    receive do
      {:call, call} -> handle_call(call, state)
    after
      5000 -> :ok
    end
  end

  def handle_call(call, %State{} = state) do
    result = GenServer.call(state.server_pid, call)
    send(state.client_pid, result)
    loop(state)
  end
end
