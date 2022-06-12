defmodule EmporiumNexus.InferenceEndpoint do
  @moduledoc """
  The Inference Endpoint is added to an existing WebRTC Engine which runs the Inference Session, 
  responsible for carrying out inference on frames from each added track, which represents video
  sent from the client via WebRTC.
  """

  use Membrane.Bin
  require Membrane.Logger
  alias Membrane.RTC.Engine
  alias Membrane.RTC.Engine.Endpoint.WebRTC.TrackReceiver
  alias Membrane.RTC.Engine.Track
  alias EmporiumNexus.VideoOrientationTracker
  alias EmporiumNexus.VideoOrientationExtension
  alias EmporiumNexus.VideoFormatTracker
  alias Membrane.WebRTC.Extension
  alias EmporiumNexus.InferenceSink

  def_input_pad :input,
    demand_unit: :buffers,
    accepted_format: _any,
    availability: :on_request

  def_options rtc_engine_pid: [
                spec: pid(),
                description: "Pid of RTC Engine"
              ],
              owner_pid: [
                spec: pid(),
                description: "Pid of parent where notifications will be sent to"
              ]

  @impl Membrane.Bin
  def handle_init(_ctx, %{rtc_engine_pid: rtc_engine_pid, owner_pid: owner_pid}) do
    state = %{rtc_engine_pid: rtc_engine_pid, owner_pid: owner_pid, tracks: %{}, active: false}
    {[], state}
  end

  @impl true
  def handle_parent_notification({:new_tracks, tracks}, ctx, state) do
    {:endpoint, endpoint_id} = ctx.name

    tracks =
      Enum.reduce(tracks, state.tracks, fn track, tracks ->
        with true <- should_subscribe_track?(track) do
          :ok = Engine.subscribe(state.rtc_engine_pid, endpoint_id, track.id)
          Map.put(tracks, track.id, track)
        else
          false -> tracks
        end
      end)

    {[], %{state | tracks: tracks}}
  end

  @impl true
  def handle_parent_notification(_msg, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_child_notification({:variant_switched, _variant, _reason}, _child, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_child_notification(
        {:format_changed, format},
        {:video_format_tracker, _track_id},
        _ctx,
        %{active: true} = state
      ) do
    send(state.owner_pid, {:format_changed, format})
    {[], state}
  end

  @impl true
  def handle_child_notification(
        {:orientation_changed, data},
        {:video_orientation_tracker, track_id},
        _ctx,
        %{active: true} = state
      ) do
    send(state.owner_pid, {:orientation_changed, data})
    {[{:notify_child, {{:inferrer, track_id}, {:orientation_changed, data}}}], state}
  end

  @impl true
  def handle_child_notification(_notification, _child, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_spec_started(children, _ctx, state) do
    if Enum.any?(children, fn
         {:inferrer, _} -> true
         _ -> false
       end) do
      {[], %{state | active: true}}
    else
      {[], state}
    end
  end

  @impl true
  def handle_pad_added(Pad.ref(:input, track_id) = input_pad, _ctx, state) do
    track = Map.fetch!(state.tracks, track_id)
    child_spec = build_child_spec(input_pad, track, state.owner_pid)
    {[spec: child_spec], state}
  end

  defp build_child_spec(input_pad, track, owner_pid) do
    uri = VideoOrientationExtension.uri()
    [id] = get_in(track.ctx, [Extension, Access.filter(&(&1.uri == uri)), Access.key(:id)])

    track_receiver = %TrackReceiver{track: track, initial_target_variant: :high}
    track_depayloader = Track.get_depayloader(track)
    video_orientation_tracker = %VideoOrientationTracker{extension_id: id}
    h264_parser = %Membrane.H264.FFmpeg.Parser{alignment: :au, attach_nalus?: true}
    h264_decoder = Membrane.H264.FFmpeg.Decoder
    video_size_tracker = VideoFormatTracker
    inference_sink = %InferenceSink{owner_pid: owner_pid}

    [
      bin_input(input_pad)
      |> child({:track_receiver, track.id}, track_receiver)
      |> child({:depayloader, track.id}, track_depayloader)
      |> child({:video_orientation_tracker, track.id}, video_orientation_tracker)
      |> child({:parser, track.id}, h264_parser)
      |> child({:decoder, track.id}, h264_decoder)
      |> child({:video_format_tracker, track.id}, video_size_tracker)
      |> child({:inferrer, track.id}, inference_sink)
    ]
  end

  defp should_subscribe_track?(%Membrane.RTC.Engine.Track{} = track) do
    cond do
      track.type != :video -> false
      true -> Enum.member?([:H264], track.encoding)
    end
  end
end
