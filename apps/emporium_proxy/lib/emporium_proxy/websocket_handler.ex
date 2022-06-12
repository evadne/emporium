defmodule EmporiumProxy.WebsocketHandler do
  @moduledoc """
  Module responsible for handling all Websockets traffic.

  Since Phoenix 1.7, the Cowboy2 handler for Websocket has been removed and replaced with
  an unified module Plug.Cowboy.Handler in plug_cowboy. Simply removing the path prefix
  (due to the script_name not having been fixed & configured) is however not enough for the
  workflow to work properly, as the upgrade function would be called with the wrong arguments.

  Hence the response from `Plug.Cowboy.Handler.init/2` is massaged slightly.
  """

  @upstream Plug.Cowboy.Handler

  def init(request, {{endpoint, mount}, options}) do
    request_path = String.replace_prefix(request.path, mount, "")
    request = %{request | path: request_path}

    case @upstream.init(request, {endpoint, options}) do
      {@upstream, req, state, options} -> {__MODULE__, req, state, options}
      {:ok, req, {endpoint, opts}} -> {:ok, req, {endpoint, opts}}
    end
  end

  def upgrade(req, env, __MODULE__, state, options) do
    @upstream.upgrade(req, env, @upstream, state, options)
  end
end
