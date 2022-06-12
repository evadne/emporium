defmodule EmporiumNexus.Mixfile do
  use Mix.Project

  def project do
    [
      app: :emporium_nexus,
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
      mod: {EmporiumNexus.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    # - membrane_core: use-push-flow-0.11 is a branch based on 0.11.3 in March 2023
    membrane_core = [github: "membraneframework/membrane_core", branch: "use-push-flow-0.11"]

    [
      {:briefly, "~> 0.4.1"},
      {:emporium_environment, in_umbrella: true},
      {:emporium_inference_yolov5, in_umbrella: true},
      {:membrane_core, membrane_core ++ [override: true]},
      {:membrane_rtc_engine, "~> 0.11.0", override: true}
    ]
  end
end
