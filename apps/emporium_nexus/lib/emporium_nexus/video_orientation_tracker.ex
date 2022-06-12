defmodule EmporiumNexus.VideoOrientationTracker do
  @moduledoc """
  A filter to be used in the inference pipeline to tell the Endpoint about the orientation
  that is pulled from CVO header
  """

  use Membrane.Filter
  alias Membrane.RTP.Header.Extension

  def_input_pad :input,
    availability: :always,
    accepted_format: _any,
    demand_mode: :auto

  def_output_pad :output,
    availability: :always,
    accepted_format: _any,
    demand_mode: :auto

  def_options extension_id: [
                spec: 1..14,
                description: "RTP Extension ID of the Video Orientation extension."
              ]

  @impl true
  def handle_init(_ctx, options) do
    {[], %{orientation: nil, extension_id: options.extension_id}}
  end

  @impl true
  def handle_process(:input, buffer, _ctx, %{orientation: orientation} = state) do
    buffer_action = {:buffer, {:output, buffer}}

    case Extension.find(buffer, state.extension_id) do
      nil ->
        {[buffer_action], state}

      %{data: ^orientation} ->
        {[buffer_action], state}

      %{data: data} ->
        notify_action = {:notify_parent, {:orientation_changed, data}}
        {[notify_action, buffer_action], %{state | orientation: data}}
    end
  end
end
