defmodule Siri.Consumer do
  @moduledoc false

  @behaviour Nostrum.Consumer

  alias Nostrum.Api.{Message, Channel}

  require Logger

  @spec handle_event({atom(), Nostrum.Struct.Message.t(), any()}) :: any()
  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    should_respond =
      msg.author.id != Application.get_env(:siri, :bot_id) and
        (Enum.any?(msg.mentions, fn user -> user.id == Application.get_env(:siri, :bot_id) end) or
           msg.content |> String.downcase() |> String.contains?("siri"))

    if should_respond do
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

      Task.async(fn ->
        Channel.start_typing(msg.channel_id)
      end)

      {:ok, response} =
        ExLLM.chat(
          :gemini,
          [%{role: "system", content: Siri.Prompt.system_prompt()} | messages],
          response_model: Siri.Model,
          model: "gemini-2.5-flash",
          max_retries: 2
        )

      case Map.get(response, :type) do
        :reply ->
          Message.create(msg.channel_id,
            content: response.content
          )

        :react ->
          Message.react(msg.channel_id, msg.id, Siri.Emoji.get(response.emoji))

        :react_and_reply ->
          Task.async(fn ->
            Message.react(msg.channel_id, msg.id, Siri.Emoji.get(response.emoji))
          end)

          Message.create(msg.channel_id,
            content: response.content
          )

        _ ->
          :ignore
      end

      :ignore
    else
    end
  end

  # Ignore any other events
  def handle_event(_), do: :ok
end
