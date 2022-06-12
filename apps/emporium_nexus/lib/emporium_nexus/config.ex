defmodule EmporiumNexus.Config do
  alias EmporiumNexus.KeyServer

  def get_turn_options do
    {:ok, ip} = get_turn_ip()
    {:ok, mock_ip} = get_turn_mock_ip()
    {:ok, ports_range} = get_turn_ports_range()
    options = [ip: ip, mock_ip: mock_ip, ports_range: ports_range]

    case get_turn_tls_certificate_path() do
      {:ok, path} -> [cert_file: path] ++ options
      _ -> [cert_file: nil] ++ options
    end
  end

  def get_rtc_network_options do
    {:ok, dtls_cert} = GenServer.call(KeyServer, :get_dtls_cert)
    {:ok, dtls_pkey} = GenServer.call(KeyServer, :get_dtls_pkey)

    [
      integrated_turn_options: get_turn_options(),
      integrated_turn_domain: nil,
      dtls_pkey: dtls_pkey,
      dtls_cert: dtls_cert
    ]
  end

  def get_webrtc_extensions(options) do
    alias Membrane.WebRTC.Extension.{Mid, RepairedRid, Rid, TWCC, VAD}
    alias EmporiumNexus.VideoOrientationExtension, as: VideoOrientation
    extensions = [TWCC, VideoOrientation]

    Enum.reduce(options, extensions, fn
      :simulcast, extensions -> [Mid, Rid, RepairedRid] ++ extensions
      :voice_activity_detection, extensions -> [VAD] ++ extensions
    end)
  end

  def get_webrtc_handshake_options do
    {:ok, dtls_cert} = GenServer.call(KeyServer, :get_dtls_cert)
    {:ok, dtls_pkey} = GenServer.call(KeyServer, :get_dtls_pkey)
    [client_mode: false, dtls_srtp: true, pkey: dtls_pkey, cert: dtls_cert]
  end

  defp get_turn_ip do
    case System.fetch_env("TURN_IP") do
      {:ok, value} -> parse_address(value)
      :error -> {:ok, {0, 0, 0, 0}}
    end
  end

  defp get_turn_mock_ip do
    case System.fetch_env("TURN_MOCK_IP") do
      {:ok, value} when is_binary(value) -> parse_address(value)
      :error -> get_turn_ip()
    end
  end

  defp get_turn_ports_range do
    with {:ok, value_from} <- System.fetch_env("TURN_PORT_UDP_FROM"),
         {:ok, value_to} <- System.fetch_env("TURN_PORT_UDP_TO"),
         {:ok, from_port} <- parse_port(value_from),
         {:ok, to_port} <- parse_port(value_to),
         true <- from_port > 1024,
         true <- from_port <= to_port do
      {:ok, {from_port, to_port}}
    else
      _ -> :error
    end
  end

  def get_turn_tcp_port do
    with {:ok, value} <- System.fetch_env("TURN_PORT_TCP"),
         {:ok, port} <- parse_port(value) do
      {:ok, port}
    else
      _ -> {:ok, nil}
    end
  end

  def get_turn_tls_port do
    with {:ok, value} <- System.fetch_env("TURN_PORT_TLS"),
         {:ok, port} <- parse_port(value) do
      {:ok, port}
    else
      _ -> :error
    end
  end

  def get_turn_tls_certificate_path do
    System.fetch_env("TURN_CERT_TLS")
  end

  defp parse_port(port_value) do
    with true <- is_binary(port_value),
         port when port in 1..65_535 <- String.to_integer(port_value) do
      {:ok, port}
    else
      _ -> :error
    end
  end

  defp parse_address(value) do
    case value |> to_charlist() |> :inet.parse_address() do
      {:ok, address} -> {:ok, address}
      {:error, :einval} -> :error
    end
  end
end
