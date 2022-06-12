defmodule EmporiumProxy.Mixfile do
  use Mix.Project

  def project do
    [
      app: :emporium_proxy,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      deps: proxy_deps() ++ deps()
    ]
  end

  def application do
    [
      mod: {EmporiumProxy.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp proxy_deps do
    (Application.get_env(:emporium_proxy, EmporiumProxy) || [])
    |> Keyword.get(:applications, [])
    |> Enum.map(&{&1, in_umbrella: true})
  end

  defp deps do
    [
      {:emporium_environment, in_umbrella: true},
      {:phoenix, "~> 1.7.2"},
      {:plug_cowboy, "~> 2.6.1"}
    ]
  end
end
