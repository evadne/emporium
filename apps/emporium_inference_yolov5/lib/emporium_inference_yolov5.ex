defmodule EmporiumInference.YOLOv5 do
  alias EmporiumInference.Image
  alias EmporiumInference.YOLOv5.Request

  @type detection :: {
          class_id :: non_neg_integer(),
          class_name :: String.t(),
          score :: float(),
          x1 :: float(),
          x2 :: float(),
          y1 :: float(),
          y2 :: float()
        }

  @type duration :: {atom() | String.t(), non_neg_integer()}

  @spec request(Image.t()) ::
          {:ok, [detection], [duration]}
          | {:error, reason :: atom() | String.t()}

  def request(image) do
    image
    |> EmporiumInference.ImageConversion.normalise(640, 640)
    |> Request.perform()
  end
end
