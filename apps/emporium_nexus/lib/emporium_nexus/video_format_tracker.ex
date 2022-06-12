defmodule EmporiumNexus.VideoFormatTracker do
  @moduledoc """
  A filter to be used in the inference pipeline, to tell the owner about the changes in input
  formats (such as width and height of the track being streamed)
  """

  use Membrane.Filter

  def_input_pad :input,
    availability: :always,
    accepted_format: _any,
    demand_mode: :auto

  def_output_pad :output,
    availability: :always,
    accepted_format: _any,
    demand_mode: :auto

  @impl true
  def handle_init(_ctx, _options) do
    {[], %{format: nil}}
  end

  @impl true
  def handle_stream_format(:input, format, _ctx, %{format: format} = state) do
    {[forward: format], state}
  end

  @impl true
  def handle_stream_format(:input, format, _ctx, state) do
    {[notify_parent: {:format_changed, format}, forward: format], %{state | format: format}}
  end

  @impl true
  def handle_process(:input, buffer, _ctx, state) do
    {[{:buffer, {:output, buffer}}], state}
  end
end
