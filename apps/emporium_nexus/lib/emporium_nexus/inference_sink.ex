defmodule EmporiumNexus.InferenceSink do
  @moduledoc """
  The Inference Sink is responsible for running inference on incoming raw video frames.
  """

  use Membrane.Sink
  alias Membrane.Buffer
  alias Membrane.RawVideo
  alias EmporiumInference.Image
  alias EmporiumNexus.InferenceRequestor

  def_input_pad :input,
    demand_unit: :buffers,
    mode: :pull,
    accepted_format: %Membrane.RawVideo{}

  def_options owner_pid: [
                spec: pid(),
                description: "Pid of parent where notifications will be sent to"
              ]

  @impl true
  def handle_init(_ctx, %{owner_pid: owner_pid}) do
    {:ok, pid} = InferenceRequestor.start_link(owner_pid, &request_inference/2)
    {[], %{format: nil, orientation: <<0>>, requestor_pid: pid}}
  end

  @impl true
  def handle_stream_format(:input, %RawVideo{} = format, _ctx, state) do
    :ok = InferenceRequestor.request_format(state.requestor_pid, {format, state.orientation})
    {[], %{state | format: format}}
  end

  @impl true
  def handle_parent_notification({:orientation_changed, data}, _ctx, state) do
    :ok = InferenceRequestor.request_format(state.requestor_pid, {state.format, data})
    {[], %{state | orientation: data}}
  end

  @impl true
  def handle_write(:input, buffer, _ctx, state) do
    :ok = InferenceRequestor.request_buffer(state.requestor_pid, buffer)
    actions = [demand: :input]
    {actions, state}
  end

  @impl true
  def handle_event(pad, event, ctx, state) do
    super(pad, event, ctx, state)
  end

  @impl true
  def handle_terminate_request(_ctx, state) do
    {[terminate: :normal], state}
  end

  defp request_inference(%Buffer{} = buffer, {%RawVideo{} = format, orientation}) do
    image = build_image(buffer, format, orientation)
    {:ok, detections, _durations} = EmporiumInference.YOLOv5.request(image)
    {:detections, Membrane.Buffer.get_dts_or_pts(buffer), detections}
    # {:ok, classifications, _durations} = EmporiumInference.ResNet.request(image)
    # {:classifications, Membrane.Buffer.get_dts_or_pts(buffer), classifications}
  end

  defp build_image(%Buffer{} = buffer, %RawVideo{pixel_format: :I420} = format, orientation) do
    %Image{
      width: format.width,
      height: format.height,
      format: :I420,
      orientation: build_image_orientation(orientation),
      data: buffer.payload
    }
  end

  defp build_image_orientation(<<0>>), do: :upright
  defp build_image_orientation(<<1>>), do: :rotated_90_ccw
  defp build_image_orientation(<<2>>), do: :rotated_180
  defp build_image_orientation(<<3>>), do: :rotated_90_cw
end
