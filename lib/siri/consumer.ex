defmodule Siri.Consumer do
  @moduledoc false

  @behaviour Nostrum.Consumer

  alias Nostrum.Api.Message

  require Logger

  # FIXME: there has to be a better way to do this
  @bot_id 1409_583_765_151_551_498

  # @spec handle_event({:MESSAGE_CREATE, Nostrum.Struct.Message.t(), any()})
  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    # Logger.debug(msg)

    if Enum.any?(msg.mentions, fn user -> user.id == @bot_id end) do
      referenced_message = Map.get(msg.referenced_message, :content)
      currrent_message = msg.content

      messages =
        [referenced_message, currrent_message]
        |> Enum.reject(&is_nil(&1))
        |> Enum.map(fn message ->
          %{
            role: "user",
            content: message
          }
        end)

      {:ok, response} =
        ExLLM.chat(
          "gemini/gemini-2.0-flash",
          [
            %{
              role: "system",
              content: Siri.Prompt.system_prompt()
            }
            | messages
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
