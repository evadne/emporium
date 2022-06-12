defmodule EmporiumEnvironment.Endpoint do
  @moduledoc """
  Resolves the correct configuration for Phoenix Endpoints. To be used in the init function of
  Endpoints.
  """

  def init(config) do
    template = build_template()
    {template_url, template} = Keyword.pop(template, :url, [])
    {config_url, config} = Keyword.pop(config, :url, [])
    url = Keyword.put(template_url, :path, Keyword.get(config_url, :path, "/"))
    config = config |> Keyword.merge(template) |> Keyword.put(:url, url)
    {:ok, config}
  end

  defp build_template do
    [
      url: url(),
      secret_key_base: secret_key_base(),
      live_view: live_view(),
      check_origin: check_origin()
    ]
  end

  import System, only: [get_env: 1]

  defp url, do: [scheme: url_scheme(), host: url_host(), port: url_port(), path: "/"]
  defp url_scheme, do: get_env("URL_SCHEME") || "http"
  defp url_host, do: get_env("URL_HOST") || get_env("HOST") || "localhost"
  defp url_port, do: get_env("URL_PORT") || get_env("PORT")

  defp secret_key_base, do: get_env("SECRET_KEY_BASE")

  defp live_view, do: [signing_salt: live_view_signing_salt()]
  defp live_view_signing_salt, do: get_env("LIVE_VIEW_SIGNING_SALT") || secret_key_base()

  with :prod <- Mix.env() do
    defp url_hosts do
      Enum.uniq([url_host() | url_alternate_hosts()])
    end

    defp url_alternate_hosts do
      System.get_env("URL_ALTERNATE_HOSTS", "") |> String.split(",", trim: true)
    end

    defp check_origin do
      Enum.map(url_hosts(), &("//" <> &1))
    end
  else
    _ -> defp check_origin, do: false
  end
end
