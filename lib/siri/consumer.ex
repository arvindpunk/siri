defmodule Siri.Consumer do
  @moduledoc false

  @behaviour Nostrum.Consumer

  alias Nostrum.Api.Message

  require Logger

  # FIXME: there has to be a better way to do this
  @bot "<@1409583765151551498> "

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    case msg.content do
      @bot <> user_prompt ->
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

        {:ok, _message} =
          Message.create(msg.channel_id,
            content: response.content
          )

      _ ->
        :ignore
    end
  end

  # Ignore any other events
  def handle_event(_), do: :ok
end
