defmodule Siri.Consumer do
  @moduledoc false

  @behaviour Nostrum.Consumer

  alias Nostrum.Api.{Message, Channel}

  require Logger

  @spec handle_event({atom(), Nostrum.Struct.Message.t(), any()}) :: any()
  def handle_event({:MESSAGE_CREATE, current_message, _ws_state}) do
    should_respond =
      current_message.author.id != Application.get_env(:siri, :bot_id) and
        (Enum.any?(current_message.mentions, fn user ->
           user.id == Application.get_env(:siri, :bot_id)
         end) or
           current_message.content |> String.downcase() |> String.contains?("siri"))

    # Logger.debug(should_respond: should_respond, msg: current_message)

    if should_respond do
      Task.async(fn ->
        Channel.start_typing(current_message.channel_id)
      end)

      with {:ok, previous_messages} <-
             Channel.messages(
               current_message.channel_id,
               4,
               {:before, current_message.id}
             ),
           {:ok, response} <-
             (
               referenced_message = current_message.referenced_message

               previous_messages =
                 previous_messages
                 |> Enum.reject(fn message ->
                   is_nil(message) or
                     (not is_nil(referenced_message) and message.id == referenced_message.id)
                 end)

               previous_messages =
                 if not is_nil(referenced_message),
                   do: previous_messages ++ [referenced_message],
                   else: previous_messages

               messages =
                 (previous_messages ++ [current_message])
                 |> Enum.map(fn message ->
                   %{
                     role: "user",
                     content: """
                       user_id: <@#{message.author.id}>
                       nick: #{message.author.username}
                       body: #{message.content}
                     """
                   }
                 end)

               ExLLM.chat(
                 :gemini,
                 [%{role: "system", content: Siri.Prompt.system_prompt()} | messages],
                 #  response_model: Siri.Model,
                 model: "gemini-2.5-pro",
                 max_retries: 2,
                 safety_settings: [
                   %{
                     category: "HARM_CATEGORY_HARASSMENT",
                     threshold: "BLOCK_NONE"
                   },
                   %{
                     category: "HARM_CATEGORY_HATE_SPEECH",
                     threshold: "BLOCK_NONE"
                   },
                   %{
                     category: "HARM_CATEGORY_SEXUALLY_EXPLICIT",
                     threshold: "BLOCK_NONE"
                   },
                   %{
                     category: "HARM_CATEGORY_DANGEROUS_CONTENT",
                     threshold: "BLOCK_NONE"
                   },
                   %{
                     category: "HARM_CATEGORY_CIVIC_INTEGRITY",
                     threshold: "BLOCK_NONE"
                   }
                 ]
               )
             ) do
        case Map.get(response, :type) do
          :reply ->
            Message.create(current_message.channel_id,
              content: response.content
            )

          :react ->
            Message.react(
              current_message.channel_id,
              current_message.id,
              Siri.Emoji.get(response.emoji)
            )

          :react_and_reply ->
            Task.async(fn ->
              Message.react(
                current_message.channel_id,
                current_message.id,
                Siri.Emoji.get(response.emoji)
              )
            end)

            Message.create(current_message.channel_id,
              content: response.content
            )

          _ ->
            Message.create(current_message.channel_id,
              content: response.content
              # "this is a placeholder message where the LLM didn't want to reply to you as the message wasn't worth replying you twat. (here for debugging purposes)"
            )
        end
      else
        {:error, msg} ->
          Message.create(current_message.channel_id, content: "error: " <> msg)
      end
    end
  end

  # Ignore any other events
  def handle_event(_), do: :ok
end
