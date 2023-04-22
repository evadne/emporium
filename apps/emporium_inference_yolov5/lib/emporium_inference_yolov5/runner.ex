defmodule EmporiumInference.YOLOv5.Runner do
  @moduledoc """
  The Runner is responsible for starting the external Model Runner process (daemon), which
  interacts with the GPU and runs inferrence, and exposing the resultant capacity via the Broker
  as a pool of Daemon Acceptors.
  """

  @otp_app Mix.Project.config()[:app]
  use GenServer
  require Logger
  alias EmporiumInference.Image

  defmodule State do
    @type t :: %__MODULE__{
            status: :pending | {:starting, ready_value :: String.t()} | :available | :failed,
            exec_pid: pid() | nil,
            exec_os_pid: non_neg_integer() | nil,
            mailbox_pid: pid() | nil,
            pending_calls: :queue.queue({message :: term(), from :: GenServer.from()}),
            pending_requests: %{required(reference()) => from :: GenServer.from()},
            pending_regions: %{required(reference()) => shmex :: Shmex.t()},
            acceptors_count: non_neg_integer(),
            acceptors_supervisor_pid: pid() | nil,
            available_regions: :queue.queue(Shmex.t())
          }
    defstruct status: :pending,
              exec_pid: nil,
              exec_os_pid: nil,
              mailbox_pid: nil,
              pending_calls: :queue.new(),
              pending_requests: %{},
              pending_regions: %{},
              acceptors_count: 1,
              acceptors_supervisor_pid: nil,
              available_regions: :queue.new()
  end

  alias EmporiumInference.YOLOv5.Acceptor

  @doc """
  Starts the Model Runner
  """
  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Called by the Runner via RPC once the model has been fully loaded
  """
  def ready(mailbox_pid, ready_value) do
    with :ok = GenServer.call(__MODULE__, {:ready, mailbox_pid, to_string(ready_value)}) do
      {:ok, mailbox_pid}
    end
  end

  @impl GenServer
  def init(_) do
    {:ok, %State{}, {:continue, :init}}
  end

  @impl GenServer
  def handle_call({:ready, mailbox_pid, x}, _from, %State{status: {:starting, x}} = state) do
    state = %{state | status: :available, mailbox_pid: mailbox_pid}
    {:ok, state} = start_acceptors(state)
    {:reply, :ok, state, {:continue, :ready}}
  end

  @impl GenServer
  def handle_call(message, from, %State{status: {:starting, _}} = state) do
    pending_calls = :queue.in({message, from}, state.pending_calls)
    state = %{state | pending_calls: pending_calls}
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(
        {:infer,
         %Image{
           width: width,
           height: height,
           orientation: orientation,
           format: format,
           data: data
         }},
        from,
        %State{status: :available} = state
      ) do
    {:ok, region, state} = build_region(data, state)
    request_data = {:shm, region.size, region.capacity, region.name}
    request = {width, height, orientation, format, request_data}
    {:ok, reference, state} = send_request(:infer, request, from, state)
    state = %{state | pending_regions: put_in(state.pending_regions, [reference], region)}
    {:noreply, state}
  end

  @impl GenServer
  def handle_continue(:init, %State{status: :pending} = state) do
    _ = Process.flag(:trap_exit, true)
    {:ok, pid, os_pid, ready_value} = start_runner()
    {:noreply, %{state | status: {:starting, ready_value}, exec_pid: pid, exec_os_pid: os_pid}}
  end

  @impl GenServer
  def handle_continue(:ready, %State{status: :available} = state) do
    with {{:value, {message, from}}, queue} <- :queue.out(state.pending_calls),
         state = %{state | pending_calls: queue},
         {:noreply, state} <- handle_call(message, from, state) do
      {:noreply, state, {:continue, :ready}}
    else
      {:empty, _queue} -> {:noreply, state}
      _ -> {:stop, :error}
    end
  end

  @impl GenServer
  def handle_info({:stdout, _os_pid, message}, %State{} = state) do
    for line <- String.split(message, "\n"), line = String.trim(line), line != "" do
      _ = Logger.info(line)
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:stderr, _os_pid, message}, %State{} = state) do
    for line <- String.split(message, "\n"), line = String.trim(line), line != "" do
      _ = Logger.error(line)
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:EXIT, pid, _}, %State{exec_pid: pid} = state) do
    {:stop, :bad_executable, %{state | status: :failed}}
  end

  @impl GenServer
  def handle_info({:EXIT, _, _}, %State{} = state) do
    # Acceptor exited
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:reply, reference, result}, %State{} = state) do
    {:ok, state} = send_response(reference, result, state)
    {%Shmex{} = region, pending_regions} = pop_in(state.pending_regions, [reference])
    available_regions = :queue.in(region, state.available_regions)
    {:noreply, %{state | pending_regions: pending_regions, available_regions: available_regions}}
  end

  defp send_request(command, payload, from, state) do
    reference = make_ref()
    call = {:call, self(), reference, command, payload}
    pending_requests = put_in(state.pending_requests, [reference], from)
    state = %{state | pending_requests: pending_requests}
    send(state.mailbox_pid, call)
    {:ok, reference, state}
  end

  defp send_response(reference, result, state) do
    {from, pending_requests} = pop_in(state.pending_requests, [reference])
    :ok = GenServer.reply(from, result)
    state = %{state | pending_requests: pending_requests}
    {:ok, state}
  end

  defp start_runner do
    priv_path = Application.app_dir(@otp_app, "priv")
    executable_path = Path.join(priv_path, "runner")
    model_path = Path.join(priv_path, get_model_name())
    ready_module = to_string(__MODULE__)
    ready_function = to_string("ready")
    ready_value = to_string(:erlang.unique_integer([:positive]))
    logger_level = to_string(Logger.level())

    environment = [
      {"NODE_NAME", to_string(Node.self())},
      {"NODE_COOKIE", to_string(Node.get_cookie())},
      {"MODEL_PATH", model_path},
      {"READY_MODULE", ready_module},
      {"READY_FUNCTION", ready_function},
      {"READY_VALUE", ready_value},
      {"LOGGER_LEVEL", logger_level}
    ]

    options = [
      {:stdout, self()},
      {:stderr, self()},
      {:env, [:clear | environment]}
    ]

    with {:ok, pid, os_pid} <- :exec.run_link([to_string(executable_path)], options) do
      {:ok, pid, os_pid, ready_value}
    end
  end

  defp start_acceptors(state) do
    {:ok, pid} = DynamicSupervisor.start_link([])

    for _ <- 1..state.acceptors_count do
      {:ok, _} = DynamicSupervisor.start_child(pid, {Acceptor, self()})
    end

    {:ok, %{state | acceptors_supervisor_pid: pid}}
  end

  defp get_model_name do
    Application.get_env(@otp_app, :model_name, "yolov5s.torchscript")
  end

  defp build_region(data, state) do
    with {{:value, region}, queue} <- :queue.out(state.available_regions) do
      if byte_size(data) != region.capacity do
        region = Shmex.new(data)
        {:ok, region, %{state | available_regions: :queue.new()}}
      else
        {:ok, region} = Shmex.Native.write(region, data)
        {:ok, region, %{state | available_regions: queue}}
      end
    else
      {:empty, _queue} -> {:ok, Shmex.new(data), state}
    end
  end
end
