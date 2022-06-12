defmodule EmporiumNexus.VideoOrientationExtension do
  @moduledoc """
  Module implementing `Membrane.WebRTC.Extension` behaviour for Coordination of Video Orientation 
  (CVO) inside the RTP Header.

  This extension is described at:

  https://www.tech-invite.com/3m26/toc/tinv-3gpp-26-114_f.html
  https://www.arib.or.jp/english/html/overview/doc/STD-T63V12_00/5_Appendix/Rel13/26/26114-d30.pdf
  """
  @behaviour Membrane.WebRTC.Extension
  alias ExSDP.Attribute.Extmap
  alias ExSDP.Media
  alias Membrane.WebRTC.Extension

  @name :video_orientation
  @uri "urn:3gpp:video-orientation"

  @impl true
  def new(opts \\ Keyword.new()),
    do: %Extension{
      module: __MODULE__,
      rtp_opts: opts,
      uri: @uri,
      name: @name
    }

  @impl Membrane.WebRTC.Extension
  def compatible?(:H264), do: true
  def compatible?(:VP8), do: true
  def compatible?(_), do: false

  @impl Membrane.WebRTC.Extension
  def get_rtp_module(_extmap_extension_id, _options, _track_type) do
    :no_rtp_module
  end

  @impl Membrane.WebRTC.Extension
  def add_to_media(media, id, _direction, _payload_types) do
    media
    |> Media.add_attribute(%Extmap{id: id, uri: @uri})
  end

  @impl Membrane.WebRTC.Extension
  def uri do
    @uri
  end
end
