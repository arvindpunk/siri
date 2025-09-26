defmodule Siri.Consumer do
  @moduledoc false

  @behaviour Nostrum.Consumer

  require Logger

  @spec handle_event({atom(), Nostrum.Struct.Message.t(), any()}) :: any()
  def handle_event({:MESSAGE_CREATE, current_message, _ws_state}) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        Siri.ChannelSupervisor,
        {Siri.ChannelHandler, %{channel_id: current_message.channel_id, messages: []}}
      )

    GenServer.cast(pid, {:message, current_message})
  end

  # Ignore any other events
  def handle_event(_), do: :ok
end
