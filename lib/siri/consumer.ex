defmodule Siri.Consumer do
  @moduledoc false

  @behaviour Nostrum.Consumer

  alias Nostrum.Api.Message

  require Logger

  # FIXME: there has to be a better way to do this
  @bot_id 1409_583_765_151_551_498

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    if Enum.any?(msg.mentions, fn user -> user.id == @bot_id end) do
      user_prompt = msg.content

      {:ok, response} =
        ExLLM.chat(
          "gemini/gemini-2.0-flash",
          [
            %{
              role: "system",
              content: Siri.Prompt.system_prompt()
            },
            %{
              role: "user",
              content: user_prompt
            }
          ]
        )

      Message.create(msg.channel_id,
        content: response.content
      )
    else
    end
  end

  # Ignore any other events
  def handle_event(_), do: :ok
end
