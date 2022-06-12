defmodule Emporium.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      releases: releases()
    ]
  end

  defp deps do
    # elixir_make requires a patched release beyond 0.7.6 due to patch:
    # https://github.com/elixir-lang/elixir_make/commit/58fe5b705d451a9ddf13673a785a46cda07909dc
    [
      {:dialyxir, "~> 1.1.0", only: [:dev, :test], runtime: false},
      {:elixir_make,
       github: "elixir-lang/elixir_make", ref: "58fe5b7", runtime: false, override: true}
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix, :mnesia, :iex, :ex_unit],
      flags: ~w(error_handling no_opaque underspecs unmatched_returns)a,
      ignore_warnings: "dialyzer-ignore-warnings.exs",
      list_unused_filters: true
    ]
  end

  defp releases do
    [
      emporium: [
        version: "0.0.1",
        include_executables_for: [:unix],
        applications: [
          emporium_environment: :permanent,
          emporium_inference: :permanent,
          emporium_inference_resnet: :permanent,
          emporium_inference_yolov5: :permanent,
          emporium_nexus: :permanent,
          emporium_proxy: :permanent,
          emporium_web: :permanent
        ]
      ]
    ]
  end
end
