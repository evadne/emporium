defmodule EmporiumNexus.InferenceSession do
  @moduledoc """
  Encapsulates a single-user interactive session for object inference utilising WebRTC for video
  ingestion.
  """

  use GenServer
  require Membrane.Logger
  require Membrane.OpenTelemetry
  alias EmporiumNexus.Config
  alias EmporiumNexus.InferenceEndpoint
  alias Membrane.ICE.TURNManager
  alias Membrane.RTC.Engine
  alias Membrane.RTC.Engine.Endpoint.WebRTC
  alias Membrane.RTC.Engine.Endpoint.WebRTC.SimulcastConfig
  alias Membrane.RTC.Engine.Message.EndpointCrashed
  alias Membrane.RTC.Engine.Message.EndpointMessage
  alias Membrane.WebRTC.Track.Encoding

  @type option :: {:session_id, term()} | {:simulcast?, true | false}

  @spec start_link([option], GenServer.options()) :: GenServer.on_start()
  def start_link(init_arg, options \\ []) do
    GenServer.start_link(__MODULE__, init_arg, options)
  end

  @spec add_peer_channel(pid(), pid(), String.t()) :: :ok
  def add_peer_channel(session_pid, peer_channel_pid, peer_id) do
    GenServer.call(session_pid, {:add_peer, peer_channel_pid, peer_id})
  end

  @spec session_span_id(String.t()) :: String.t()
  def session_span_id(id), do: "session:#{id}"

  @impl true
  def init(options) do
    {:ok, session_id} = Keyword.fetch(options, :session_id)
    {:ok, simulcast?} = Keyword.fetch(options, :simulcast?)

    Logger.metadata(session_id: session_id)
    Membrane.Logger.info("Spawning room process: #{inspect(self())}")

    trace_ctx = Membrane.OpenTelemetry.new_ctx()
    _ = Membrane.OpenTelemetry.attach(trace_ctx)

    span_id = session_span_id(session_id)
    session_span = Membrane.OpenTelemetry.start_span(span_id)
    _ = Membrane.OpenTelemetry.set_attributes(span_id, tracing_metadata())

    turn_options = Config.get_turn_options()
    rtc_network_options = Config.get_rtc_network_options()

    with {:ok, port} <- Config.get_turn_tcp_port() do
      TURNManager.ensure_tcp_turn_launched(turn_options, port: port)
    end

    with {:ok, port} <- Config.get_turn_tls_port(),
         {:ok, _path} <- Config.get_turn_tls_certificate_path() do
      TURNManager.ensure_tls_turn_launched(turn_options, port: port)
    end

    rtc_engine_options = [id: session_id, trace_ctx: trace_ctx, parent_span: session_span]
    {:ok, rtc_engine_pid} = Membrane.RTC.Engine.start_link(rtc_engine_options, [])
    Engine.register(rtc_engine_pid, self())

    {:ok,
     %{
       session_id: session_id,
       rtc_engine_pid: rtc_engine_pid,
       peer_id: nil,
       peer_channel_pid: nil,
       network_options: rtc_network_options,
       trace_ctx: trace_ctx,
       simulcast?: simulcast?
     }}
  end

  @impl true
  def handle_call({:add_peer, peer_channel_pid, peer_id}, _from, %{peer_id: nil} = state) do
    state = %{state | peer_channel_pid: peer_channel_pid, peer_id: peer_id}
    send(peer_channel_pid, {:simulcast_config, state.simulcast?})
    Process.monitor(peer_channel_pid)
    Membrane.Logger.info("New peer: #{inspect(peer_id)}. Accepting.")
    peer_node = node(peer_channel_pid)

    inference_endpoint = %InferenceEndpoint{
      rtc_engine_pid: state.rtc_engine_pid,
      owner_pid: peer_channel_pid
    }

    :ok = Engine.add_endpoint(state.rtc_engine_pid, inference_endpoint, endpoint_id: "inference")

    rtc_endpoint = %WebRTC{
      rtc_engine: state.rtc_engine_pid,
      ice_name: peer_id,
      owner: self(),
      integrated_turn_options: state.network_options[:integrated_turn_options],
      integrated_turn_domain: state.network_options[:integrated_turn_domain],
      handshake_opts: Config.get_webrtc_handshake_options(),
      log_metadata: [peer_id: peer_id],
      trace_context: state.trace_ctx,
      webrtc_extensions: Config.get_webrtc_extensions((state.simulcast? && [:simulcast]) || []),
      rtcp_sender_report_interval: Membrane.Time.seconds(5),
      rtcp_receiver_report_interval: Membrane.Time.seconds(5),
      filter_codecs: &filter_codecs/1,
      toilet_capacity: 1000,
      simulcast_config: %SimulcastConfig{
        enabled: state.simulcast?,
        initial_target_variant: fn _track -> :high end
      }
    }

    :ok =
      Engine.add_endpoint(state.rtc_engine_pid, rtc_endpoint, peer_id: peer_id, node: peer_node)

    {:reply, :ok, state}
  end

  def handle_call({:add_peer, _, _}, _from, state) do
    {:reply, {:error, :occupied}, state}
  end

  @impl true
  def handle_info(%EndpointMessage{message: {:media_event, data}}, state) do
    send(state.peer_channel_pid, {:media_event, data})
    {:noreply, state}
  end

  @impl true
  def handle_info(%EndpointCrashed{}, state) do
    send(state.peer_channel_pid, :endpoint_crashed)
    {:noreply, state}
  end

  @impl true
  def handle_info({:media_event, to, event}, state) do
    Engine.message_endpoint(state.rtc_engine_pid, to, {:media_event, event})
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{peer_channel_pid: pid} = state) do
    peer_id = state.peer_id
    Membrane.Logger.info("Peer #{inspect(state.peer_id)} left")
    Engine.remove_endpoint(state.rtc_engine_pid, peer_id)
    Membrane.Logger.info("Terminating engine.")

    with :ok <- Engine.terminate(state.rtc_engine_pid, blocking?: true) do
      Membrane.Logger.info("Engine terminated.")
      {:stop, :normal, state}
    else
      _ ->
        _ = Process.exit(state.rtc_engine_pid, :kill)
        {:stop, :normal, state}
    end
  end

  defp filter_codecs(%Encoding{name: "H264", format_params: fmtp}) do
    import Bitwise

    # Only accept constrained baseline
    # based on RFC 6184, Table 5.
    case fmtp.profile_level_id >>> 16 do
      0x42 -> (fmtp.profile_level_id &&& 0x00_4F_00) == 0x00_40_00
      0x4D -> (fmtp.profile_level_id &&& 0x00_8F_00) == 0x00_80_00
      0x58 -> (fmtp.profile_level_id &&& 0x00_CF_00) == 0x00_C0_00
      _otherwise -> false
    end
  end

  defp filter_codecs(_rtp_mapping), do: false

  defp tracing_metadata() do
    [
      {:"library.language", :erlang},
      {:"library.name", :membrane_rtc_engine},
      {:"library.version", "server:#{Application.spec(:membrane_rtc_engine, :vsn)}"}
    ]
  end
end
