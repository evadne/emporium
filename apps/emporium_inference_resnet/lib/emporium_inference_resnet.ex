defmodule EmporiumInference.ResNet do
  alias EmporiumInference.Image
  alias EmporiumInference.ResNet.Serving

  @type classification :: {
          label :: String.t(),
          score :: float()
        }

  @type duration :: {atom() | String.t(), non_neg_integer()}

  @spec request(Image.t()) ::
          {:ok, [classification], [duration]}
          | {:error, reason :: atom() | String.t()}

  def request(image) do
    image
    |> EmporiumInference.ImageConversion.normalise(640, 640)
    |> EmporiumInference.ImageConversion.to_mat()
    |> Serving.perform()
  end
end
