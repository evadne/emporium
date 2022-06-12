defmodule EmporiumInference.YOLOv5.Request do
  alias EmporiumInference.YOLOv5.Broker

  def perform(image, timeout \\ :infinity) do
    fn pid ->
      send_call(pid, {:infer, image}, timeout)
    end
    |> ask(timeout)
    |> handle_infer()
  end

  defp ask(callback, timeout) do
    :sbroker.dynamic_ask(Broker, self())
    |> handle_broker(callback, timeout)
  end

  defp handle_broker({:go, _, pid, _, _}, callback, _timeout) do
    callback.(pid)
  end

  defp handle_broker({:await, tag, _}, callback, timeout) do
    :sbroker.await(tag, :infinity)
    |> handle_broker(callback, timeout)
  end

  defp handle_broker({:drop, _}, _callback, _timeout) do
    {:error, :dropped}
  end

  defp handle_infer({:ok, detections, durations}) do
    {:ok, replace_class_names(detections), durations}
  end

  defp handle_infer({:error, reason}) do
    {:error, reason}
  end

  defp replace_class_names(detections) do
    for detection <- detections, {:ok, class_id} = Map.fetch(detection, :class_id) do
      Map.put(detection, :class_name, get_class_name(class_id))
    end
  end

  defp send_call(pid, call, timeout) do
    send(pid, {:call, call})

    receive do
      {:ok, results, durations} -> {:ok, results, durations}
      {:error, reason} -> {:error, reason}
    after
      timeout -> {:error, :timeout}
    end
  end

  def get_class_name(class_id) do
    [
      "person",
      "bicycle",
      "car",
      "motorcycle",
      "airplane",
      "bus",
      "train",
      "truck",
      "boat",
      "traffic light",
      "fire hydrant",
      "stop sign",
      "parking meter",
      "bench",
      "bird",
      "cat",
      "dog",
      "horse",
      "sheep",
      "cow",
      "elephant",
      "bear",
      "zebra",
      "giraffe",
      "backpack",
      "umbrella",
      "handbag",
      "tie",
      "suitcase",
      "frisbee",
      "skis",
      "snowboard",
      "sports ball",
      "kite",
      "baseball bat",
      "baseball glove",
      "skateboard",
      "surfboard",
      "tennis racket",
      "bottle",
      "wine glass",
      "cup",
      "fork",
      "knife",
      "spoon",
      "bowl",
      "banana",
      "apple",
      "sandwich",
      "orange",
      "broccoli",
      "carrot",
      "hot dog",
      "pizza",
      "donut",
      "cake",
      "chair",
      "couch",
      "potted plant",
      "bed",
      "dining table",
      "toilet",
      "tv",
      "laptop",
      "mouse",
      "remote",
      "keyboard",
      "cell phone",
      "microwave",
      "oven",
      "toaster",
      "sink",
      "refrigerator",
      "book",
      "clock",
      "vase",
      "scissors",
      "teddy bear",
      "hair drier",
      "toothbrush"
    ]
    |> Enum.at(class_id)
  end
end
