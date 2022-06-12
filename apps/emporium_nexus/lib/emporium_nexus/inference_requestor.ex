defmodule EmporiumNexus.InferenceRequestor do
  def request_format(pid, format) do
    GenServer.call(pid, {:request_format, format})
  end

  def request_buffer(pid, buffer) do
    GenServer.call(pid, {:request_buffer, buffer})
  end

  def start_link(owner_pid, request_fun) do
    GenServer.start_link(__MODULE__, {owner_pid, request_fun})
  end

  defmodule State do
    defstruct owner_pid: nil,
              request_pid: nil,
              request_fun: nil,
              pending_format: nil,
              pending_buffer: nil
  end

  def init({owner_pid, request_fun}) do
    _ = Process.flag(:trap_exit, true)
    _ = Process.monitor(owner_pid)
    {:ok, %State{owner_pid: owner_pid, request_fun: request_fun}}
  end

  def handle_call({:request_format, format}, _from, state) do
    {:reply, :ok, %{state | pending_format: format, pending_buffer: nil}}
  end

  def handle_call({:request_buffer, _buffer}, _from, %State{pending_format: nil} = state) do
    {:reply, :ok, state}
  end

  def handle_call({:request_buffer, buffer}, _from, %State{pending_buffer: nil} = state) do
    {:reply, :ok, %{state | pending_buffer: buffer}, {:continue, :request_upstream}}
  end

  def handle_call({:request_buffer, buffer}, _from, %State{} = state) do
    {:reply, :ok, %{state | pending_buffer: buffer}}
  end

  def handle_info({:DOWN, _, :process, pid, _}, %State{owner_pid: pid} = state) do
    {:stop, :normal, state}
  end

  def handle_info({:EXIT, pid, _reason}, %State{owner_pid: pid} = state) do
    {:stop, :normal, state}
  end

  def handle_info({:EXIT, pid, _reason}, %State{request_pid: pid, pending_buffer: nil} = state) do
    {:noreply, %{state | request_pid: nil}}
  end

  def handle_info({:EXIT, pid, _reason}, %State{request_pid: pid} = state) do
    {:noreply, %{state | request_pid: nil}, {:continue, :request_upstream}}
  end

  def handle_info({:EXIT, _pid, _reason}, state) do
    {:noreply, state}
  end

  def handle_continue(:request_upstream, state) do
    spawn_link(fn ->
      reply = state.request_fun.(state.pending_buffer, state.pending_format)
      send(state.owner_pid, reply)
    end)
    |> (&{:noreply, %{state | request_pid: &1}}).()
  end
end
