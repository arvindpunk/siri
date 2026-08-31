defmodule Siri.ChannelHandler do
  @moduledoc false
  use GenServer

  alias Nostrum.Api.{Message, Channel}

  require Logger

  @type state() :: %{
          channel_id: integer(),
          messages: list(Nostrum.Struct.Message.t())
        }

  @spec start_link(state()) :: {:ok, pid()} | {:error, any()}
  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: {:global, "channel::#{state.channel_id}"})
    |> case do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_cast({:message, current_message}, state) do
    state = %{state | messages: [current_message | state.messages]}
    current_content = message_content(current_message)

    should_respond =
      current_message.author.id != Application.get_env(:siri, :bot_id) and
        (Enum.any?(current_message.mentions, fn user ->
           user.id == Application.get_env(:siri, :bot_id)
         end) or
           current_content
           |> String.downcase()
           |> String.contains?(
             Application.get_env(:siri, :bot_name)
             |> String.downcase()
           ))

    if should_respond do
      Task.async(fn ->
        Channel.start_typing(current_message.channel_id)
      end)

      Task.async(fn ->
        messages =
          state.messages
          |> Enum.take(50)
          |> Enum.reverse()
          |> Enum.map(fn message ->
            if message.author.id == Application.get_env(:siri, :bot_id) do
              %{
                role: "assistant",
                content: message_content(message)
              }
            else
              %{
                role: "user",
                content:
                  "#{Enum.find_value(List.wrap(message.embeds), fn embed -> embed.author && embed.author.name end) || (message.member && message.member.nick) || message.author.username} (<@#{message.author.id}>): #{message_content(message)}"
              }
            end
          end)

        with {:ok, response} <- llm_response(messages) do
          Logger.debug("#{response.type}: #{response.content}")
          # STRUCTURED RESPONSE HANDLING
          case Map.get(response, :type) do
            :giphy ->
              Message.create(current_message.channel_id,
                content: response.content |> Siri.Substitutions.Giphy.apply_subsitition()
              )

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
                content:
                  "this is a placeholder message where the LLM didn't want to reply to you as the message wasn't worth replying, you twat. (here for debugging purposes)"
              )
          end
        else
          {:error, msg} ->
            Logger.error("error: #{msg}")
            # Message.create(current_message.channel_id, content: "error: #{msg}")
        end
      end)
    end

    state =
      if length(state.messages) > 100,
        do: %{state | messages: Enum.take(state.messages, 50)},
        else: state

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @spec message_content(Nostrum.Struct.Message.t()) :: String.t()
  def message_content(message) do
    embed_content =
      message.embeds
      |> List.wrap()
      |> Enum.flat_map(fn embed ->
        fields =
          embed.fields
          |> List.wrap()
          |> Enum.map(fn field -> "#{field.name}: #{field.value}" end)

        [embed.title, embed.description | fields]
      end)

    [message.content | embed_content]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
  end

  def llm_response(messages) do
    ExLLM.chat(
      :gemini,
      [
        %{role: "system", content: Siri.Prompt.system_prompt()}
        | messages
      ],
      response_model: Siri.Model,
      model: "gemini-3.5-flash-lite",
      max_retries: 0,
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
  end
end
