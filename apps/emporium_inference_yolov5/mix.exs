defmodule EmporiumInference.YOLOv5.Mixfile do
  use Mix.Project
  @libtorch_dir Path.join(__DIR__, "../../vendor/libtorch")

  unless File.dir?(@libtorch_dir) do
    raise "Please install libtorch in #{@libtorch_dir}"
  end

  def project do
    [
      app: :emporium_inference_yolov5,
      version: "0.1.0",
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),

      # Application
      start_permanent: Mix.env() == :prod,
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",

      # Compilers
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_targets: ["priv/runner"],
      make_clean: ["clean"],
      make_env: %{
        "LIBTORCH_INSTALL_DIR" => @libtorch_dir,
        "MIX_BUILD_EMBEDDED" => "#{Mix.Project.config()[:build_embedded]}"
      }
    ]
  end

  def application do
    [
      mod: {EmporiumInference.YOLOv5.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:emporium_inference, in_umbrella: true},
      {:elixir_make, "~> 0.7.6"},
      {:erlexec, "~> 1.21.0"},
      {:sbroker, "1.0.0"}
    ]
  end
end
