defmodule EmporiumInference.YOLOv5Test do
  use ExUnit.Case
  require Logger
  alias EmporiumInference.YOLOv5.Request
  alias EmporiumInference.Image

  setup do
    if Node.self() == :nonode@nohost do
      raise "Erlang Distribution is required to test (use ./bin/test)"
    end

    :ok
  end

  test "Can decode images" do
    paths = __DIR__ |> Path.join("../../../vendor/dataset/coco/val2017/*.jpg") |> Path.wildcard()

    if Enum.empty?(paths) do
      raise "No COCO 2017 images exist; run ./vendor/setup-coco.sh to prepare"
    end

    for path <- Stream.repeatedly(fn -> Enum.random(paths) end) |> Enum.take(10) do
      {time_load, image} =
        :timer.tc(fn ->
          mat = Evision.imread(path) |> Evision.cvtColor(Evision.Constant.cv_COLOR_BGR2RGB())
          {height, width, 3} = mat.shape
          %Image{width: width, height: height, data: Evision.Mat.to_binary(mat)}
        end)

      {time_normalise, image} =
        :timer.tc(fn ->
          EmporiumInference.ImageConversion.normalise(image, 640, 640)
        end)

      {time_perform, {:ok, detections, durations}} =
        :timer.tc(fn ->
          Request.perform(image)
        end)

      durations_preprocessing = [file_load: time_load, file_normalise: time_normalise]
      durations_processing = Keyword.new(durations)
      durations_internal = Enum.sum(for {_, v} <- durations, do: v)
      durations_overall = [comms: (time_perform - durations_internal)]
      durations_all = durations_preprocessing ++ durations_processing ++ durations_overall
      IO.inspect [Path.basename(path), detections, durations_all], limit: :infinity
    end
  end
end
