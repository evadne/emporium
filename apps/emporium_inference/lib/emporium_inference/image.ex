defmodule EmporiumInference.Image do
  @moduledoc """
  Defines the image sent to downstream inference implementations

  - `orientation`: Defines the orientation of the image as it was sent. For example, a sent
    orientation of 90° CCW (`:rotate_90_ccw`) would require correctional rortation of 90° CW
  """

  @type format :: :RGB | :I420
  @type orientation :: :upright | :rotated_90_ccw | :rotated_180 | :rotated_90_cw

  @type t :: %__MODULE__{
          width: non_neg_integer(),
          height: non_neg_integer(),
          format: format(),
          orientation: orientation(),
          data: binary()
        }

  defstruct width: 0,
            height: 0,
            format: :RGB,
            orientation: :upright,
            data: <<>>
end
