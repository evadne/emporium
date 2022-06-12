defmodule EmporiumInference.YOLOv5.Broker do
  @moduledoc """
  Connection Broker allowing graceful introduction and removal of client-side inference
  requests.

  - The Ask queue (for inference requests) uses :sbroker_codel_queue.
  - The AskR queue (for runners) uses :sbroker_drop_queue with infinity capacity.
  """

  def child_spec(init_args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [init_args]},
      type: :supervisor,
      restart: :permanent,
      shutdown: :infinity
    }
  end

  def start_link(_init_args) do
    :sbroker.start_link({:local, __MODULE__}, __MODULE__, [], [])
  end

  def init(_init_args) do
    ask_queue_spec = {:sbroker_codel_queue, %{min: 10}}
    ask_r_queue_spec = {:sbroker_drop_queue, %{max: :infinity}}
    {:ok, {ask_queue_spec, ask_r_queue_spec, []}}
  end
end
