defmodule EmporiumProxy.Router do
  use Phoenix.Router

  for {endpoint, mount} <- EmporiumProxy.get_endpoints() do
    forward(mount, endpoint)
  end
end
