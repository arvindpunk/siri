defmodule Siri.Consumer do
  @moduledoc false

  @behaviour Nostrum.Consumer

  alias Nostrum.Api.Message

  require Logger

  @bot_id 1409_583_765_151_551_498

  @spec handle_event({atom(), Nostrum.Struct.Message.t(), any()}) :: any()
  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    should_respond_without_mentioned =
      :rand.uniform() < 0.15 and msg.author.id != @bot_id and
        String.length(msg.content) > 100

    if should_respond_without_mentioned or
         Enum.any?(msg.mentions, fn user -> user.id == @bot_id end) do
      referenced_message = Map.get(msg.referenced_message || %{}, :content)
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
        # content: "[debug stuff #{length(messages)}] " <> response.content
        content: response.content
      )
    else
    end
  end

  # Ignore any other events
  def handle_event(_), do: :ok
end
