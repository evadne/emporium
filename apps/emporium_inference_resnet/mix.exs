defmodule EmporiumInference.ResNet.Mixfile do
  use Mix.Project

  def project do
    [
      app: :emporium_inference_resnet,
      version: "0.1.0",
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      start_permanent: Mix.env() == :prod,
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock"
    ]
  end

  def application do
    [
      mod: {EmporiumInference.ResNet.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    # elixir_make requires a patched release beyond 0.7.6 due to patch:
    # https://github.com/elixir-lang/elixir_make/commit/58fe5b705d451a9ddf13673a785a46cda07909dc

    [
      {:emporium_inference, in_umbrella: true},
      {:axon, "~> 0.5.1"},
      {:bumblebee, "~> 0.3.0"},
      {:exla, ">= 0.0.0"},
      {:nx, "~> 0.5.3"}
    ]
  end
end
