defmodule EmporiumInference.ImageConversion do
  alias EmporiumInference.Image

  @spec normalise(image :: Image.t(), width :: non_neg_integer(), height :: non_neg_integer()) ::
          Image.t()
  @spec to_mat(image :: Image.t()) :: Evision.Mat.t()

  def normalise(%Image{} = image, width, height) do
    image
    |> to_mat()
    |> crop(width, height)
    |> rotate_from(image.orientation)
    |> Evision.cvtColor(Evision.Constant.cv_COLOR_BGR2RGB())
    |> Evision.Mat.to_binary()
    |> then(fn data ->
      %Image{width: width, height: height, format: :RGB, orientation: :upright, data: data}
    end)
  end

  @doc """
  Converts an `EmporiumInference.Image` directly to `Evision.Mat`
  """
  def to_mat(image)

  def to_mat(%Image{format: :RGB} = image) do
    Evision.Mat.from_binary(image.data, {:u, 8}, image.height, image.width, 3)
  end

  def to_mat(%Image{format: :I420} = image) do
    Evision.Mat.from_binary(image.data, {:u, 8}, ceil(image.height * 1.5), image.width, 1)
    |> Evision.cvtColor(Evision.Constant.cv_COLOR_YUV420p2RGB())
  end

  defp crop(%Evision.Mat{shape: {image_height, image_width, _}} = mat, width, height) do
    mat
    |> Evision.Mat.roi(get_scale_fit_roi(image_width, image_height, width, height))
    |> Evision.resize({width, height})
  end

  defp rotate_from(%Evision.Mat{} = mat, orientation) do
    case orientation do
      :upright -> mat
      :rotated_90_ccw -> Evision.rotate(mat, Evision.Constant.cv_ROTATE_90_CLOCKWISE())
      :rotated_180 -> Evision.rotate(mat, Evision.Constant.cv_ROTATE_180())
      :rotated_90_cw -> Evision.rotate(mat, Evision.Constant.cv_ROTATE_90_COUNTERCLOCKWISE())
    end
  end

  defp get_scale_fit_roi(container_width, container_height, element_width, element_height) do
    scale_width = container_width / element_width
    scale_height = container_height / element_height
    scale = min(scale_width, scale_height)
    region_width = floor(scale * element_width)
    region_height = floor(scale * element_height)
    x = floor((container_width - region_width) / 2)
    y = floor((container_height - region_height) / 2)
    w = region_width
    h = region_height
    {x, y, w, h}
  end
end
