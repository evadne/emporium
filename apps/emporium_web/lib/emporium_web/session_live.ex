defmodule EmporiumWeb.SessionLive do
  use Phoenix.LiveView
  alias EmporiumNexus.InferenceSession

  @typedoc """
  Describes the status of the Session.

  - `:pending`: The LiveView was rendred initially; there is no WebRTC connection / media tracks.
  - `:acquiring`: The client has been instructed to acquire media tracks. The LiveView instructs
    the to acquire streams (event `"acquire-streams"`), and waits for `"streams-acquired"` event
  - `:connecting`: The client has been instructed to connect via WebRTC to the Inference Session
  - `:connected`: WebRTC connection is good
  - {:error, reason}: WebRTC initiation or connection issue, permission issue etc
  """
  @type status :: :pending | :acquiring | :connecting | :connected | {:error, reason :: term()}

  alias EmporiumNexus.InferenceSession

  def mount(_params, _session, socket) do
    if connected?(socket) do
      socket
      |> assign(:status, :acquiring)
      |> push_event("acquire-streams", %{})
      |> (&{:ok, &1}).()
    else
      socket
      |> assign(:status, :pending)
      |> (&{:ok, &1}).()
    end
  end

  def handle_event("streams-acquired", _params, %{assigns: %{status: :acquiring}} = socket) do
    session_id = to_string(:erlang.unique_integer([:positive]))
    peer_id = to_string(:erlang.unique_integer([:positive]))
    {:ok, session_pid} = InferenceSession.start_link(session_id: session_id, simulcast?: true)
    :ok = InferenceSession.add_peer_channel(session_pid, self(), peer_id)

    socket
    |> assign(:status, :connecting)
    |> assign(:session_id, session_id)
    |> assign(:session_pid, session_pid)
    |> assign(:peer_id, peer_id)
    |> push_event("connect-session", %{session_id: session_id, peer_id: peer_id})
    |> (&{:noreply, &1}).()
  end

  def handle_event("connected", %{"video" => %{"width" => width, "height" => height}}, socket) do
    socket
    |> assign(:status, :connected)
    |> assign(:video_width, width)
    |> assign(:video_height, height)
    |> assign(:video_orientation, <<0>>)
    |> assign(:detections, [])
    |> assign(:detections_has_hotdog, nil)
    |> assign(:classifications, [])
    |> assign(:classifications_has_hotdog, nil)
    |> update_overlay_assigns()
    |> (&{:noreply, &1}).()
  end

  def handle_event("mediaEvent", %{"data" => data}, socket) do
    send(socket.assigns.session_pid, {:media_event, socket.assigns.peer_id, data})
    {:noreply, socket}
  end

  def handle_event("error", %{"reason" => reason}, socket) do
    socket
    |> assign(:status, {:error, reason})
    |> (&{:noreply, &1}).()
  end

  def handle_info({:media_event, data}, socket) do
    socket
    |> push_event("handle-media-event", %{data: data})
    |> (&{:noreply, &1}).()
  end

  def handle_info({:detections, _timestamp, detections}, socket) do
    socket
    |> assign(:detections, build_detections(detections))
    |> assign(:detections_has_hotdog, build_detections_has_hotdog(detections))
    |> (&{:noreply, &1}).()
  end

  def handle_info({:classifications, _timestamp, classifications}, socket) do
    socket
    |> assign(:classifications, build_classifications(classifications))
    |> assign(:classifications_has_hotdog, build_classifications_has_hotdog(classifications))
    |> (&{:noreply, &1}).()
  end

  def handle_info({:simulcast_config, data}, socket) do
    socket
    |> push_event("handle-simulcast-config", %{data: data})
    |> (&{:noreply, &1}).()
  end

  def handle_info({:format_changed, %{width: width, height: height}}, socket) do
    socket
    |> assign(:video_width, width)
    |> assign(:video_height, height)
    |> update_overlay_assigns()
    |> (&{:noreply, &1}).()
  end

  def handle_info({:orientation_changed, data}, socket) do
    socket
    |> assign(:video_orientation, data)
    |> update_overlay_assigns()
    |> (&{:noreply, &1}).()
  end

  def handle_info(:endpoint_crashed, socket) do
    socket
    |> assign(:session_id, nil)
    |> assign(:session_pid, nil)
    |> assign(:peer_id, nil)
    |> assign(:status, {:error, "Backend process crashed"})
    |> (&{:noreply, &1}).()
  end

  def handle_info(_message, socket) do
    {:noreply, socket}
  end

  def render(
        %{
          status: :connected,
          video_orientation: orientation
        } = assigns
      )
      when not is_nil(orientation) do
    ~H"""
    <div id="main" phx-hook="WebRTC">
      <video id="webrtc-video" phx-update="ignore">
      </video>
      <svg id="webrtc-overlay"
        xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMidYMid meet"
        {@overlay_container}
      >
        <svg 
          xmlns="http://www.w3.org/2000/svg"
          preserveAspectRatio="xMidYMid meet"
          viewBox="0 0 640 640"
          {@overlay_viewport}
        >
          <rect stroke="white" width="640" height="640" x="0" y="0" fill="transparent" />
          <%= for %{
              rect_attributes: rect, 
              text_attributes: text,
              group_attributes: group,
              class_name: class_name,
            } <- @detections do %>
            <g class="detection" {group}>
              <rect {rect} />
              <text {text}><%= class_name %></text>
            </g>
          <% end %>
        </svg>
      </svg>
      <div id="hotdog-overlay">
        <div class="hotdog-message">
          <%= if @detections_has_hotdog || @classifications_has_hotdog do %>
            🌭 Hotdog 
          <% else %>
            ❌ Not Hotdog
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  def render(%{status: {:error, reason}} = assigns) do
    assigns = assign(assigns, :error_reason, reason)

    ~H"""
    <div id="main" phx-hook="WebRTC">
      Error: <%= @error_reason %>
    </div>
    """
  end

  def render(%{status: _} = assigns) do
    ~H"""
    <div id="main" phx-hook="WebRTC">
      <video id="webrtc-video" phx-update="ignore">
      </video>
    </div>
    """
  end

  defp build_detections(detections) do
    Enum.map(detections, fn detection ->
      Map.merge(detection, %{
        group_attributes: %{
          data_class_id: detection.class_id,
          data_class_name: detection.class_name
        },
        rect_attributes: %{
          x: detection.x1,
          y: detection.y1,
          opacity: detection.score,
          width: detection.x2 - detection.x1,
          height: detection.y2 - detection.y1
        },
        text_attributes: %{
          x: detection.x1,
          y: detection.y1
        }
      })
    end)
  end

  defp build_detections_has_hotdog(detections) do
    Enum.any?(detections, &(&1.class_name == "hot dog"))
  end

  defp build_classifications(classifications) do
    classifications
  end

  defp build_classifications_has_hotdog(classifications) do
    Enum.any?(classifications, &(String.contains?(&1.label, "hot dog") && &1.score > 0.75))
  end

  defp update_overlay_assigns(socket) do
    <<_::4, _type::1, _flip::1, orientation::2>> = socket.assigns.video_orientation
    # type: 0 = front, 1 = back 
    # flip: 0 = no, 1 = horizontal
    # orientation: 0 = 0°, 1 = 270°, 2 = 180°, 3 = 90°
    width = socket.assigns.video_width
    height = socket.assigns.video_height
    transpose = Enum.member?([1, 3], orientation)

    assign(socket,
      overlay_container: %{
        viewBox: (transpose && "0 0 #{height} #{width}") || "0 0 #{width} #{height}"
      },
      overlay_viewport: %{
        width: (transpose && height) || width,
        height: (transpose && width) || height
      }
    )
  end
end
