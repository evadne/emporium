defmodule EmporiumInference.ResNet.Serving do
  @moduledoc """
  Module-based Nx.Serving implementation for ResNet via Bumblebee
  """

  def child_spec(options \\ []) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [options]},
      type: :worker,
      restart: :permanent,
      shutdown: :brutal_kill
    }
  end

  def start_link(options) do
    serving = build_serving()
    Nx.Serving.start_link([serving: serving, name: __MODULE__] ++ options)
  end

  def perform(%Evision.Mat{} = image) do
    tensor = Evision.Mat.to_nx(image, EXLA.Backend)
    results = Nx.Serving.batched_run(__MODULE__, [tensor])
    [%{predictions: predictions}] = results
    {:ok, predictions, []}
  end

  defp build_serving do
    {:ok, model_info} = Bumblebee.load_model({:hf, "microsoft/resnet-50"})
    {:ok, featurizer} = Bumblebee.load_featurizer({:hf, "microsoft/resnet-50"})

    Bumblebee.Vision.image_classification(model_info, featurizer,
      top_k: 1,
      compile: [batch_size: 1],
      defn_options: [compiler: EXLA]
    )
  end
end
