defmodule EmporiumNexus.KeyServer do
  @moduledoc """
  Module responsible for generating DTLS key and certificate for use during WebRTC handshake.
  """

  use GenServer

  defmodule State do
    @type t :: %__MODULE__{
            dtls_cert: nil | binary(),
            dtls_pkey: nil | binary(),
            dtls_path: nil | Path.t()
          }

    defstruct dtls_cert: nil, dtls_pkey: nil, dtls_path: nil
  end

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl GenServer
  def init(_) do
    {:ok, pid} = ExDTLS.start_link(client_mode: false, dtls_srtp: true)
    {:ok, pkey} = ExDTLS.get_pkey(pid)
    {:ok, cert} = ExDTLS.get_cert(pid)
    :ok = ExDTLS.stop(pid)

    {:ok, path} = Briefly.create()
    :ok = File.chmod(path, 0o600)
    :ok = File.write(path, "#{cert}\n#{pkey}")

    {:ok, %State{dtls_cert: cert, dtls_pkey: pkey, dtls_path: path}}
  end

  @impl GenServer
  def handle_call(:get_dtls_cert, _from, state) do
    {:reply, {:ok, state.dtls_cert}, state}
  end

  @impl GenServer
  def handle_call(:get_dtls_pkey, _from, state) do
    {:reply, {:ok, state.dtls_pkey}, state}
  end

  @impl GenServer
  def handle_call(:get_dtls_path, _from, state) do
    {:reply, {:ok, state.dtls_path}, state}
  end
end
