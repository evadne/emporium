defmodule EmporiumEnvironment.MixProject do
  use Mix.Project

  def project do
    [
      app: :emporium_environment,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {EmporiumEnvironment.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:horde, "~> 0.8.4"},
      {:libcluster, "~> 3.2.2"},
      {:opentelemetry, "~> 1.0.0"},
      {:opentelemetry_exporter, "~> 1.0.4"},
      {:telemetry_metrics, "~> 0.6.1"},
      {:telemetry_poller, "~> 1.0.0"}
    ]
  end
end
