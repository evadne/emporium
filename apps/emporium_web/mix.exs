defmodule EmporiumWeb.MixProject do
  use Mix.Project

  def project do
    [
      app: :emporium_web,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.12",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:gettext] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {EmporiumWeb.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:emporium_environment, in_umbrella: true},
      {:emporium_nexus, in_umbrella: true},
      {:phoenix, "~> 1.7.2"},
      {:phoenix_html, "~> 3.3.1"},
      {:phoenix_live_reload, "~> 1.4.1", only: :dev},
      {:phoenix_live_view, "~> 0.18.18"},
      {:phoenix_view, "~> 2.0.2"},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.7.2"},
      {:gettext, "~> 0.18"},
      {:jason, "~> 1.4.0"},
      {:plug_cowboy, "~> 2.5"}
    ]
  end
end
