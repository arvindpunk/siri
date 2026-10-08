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

    should_respond =
      current_message.author.id != Application.get_env(:siri, :bot_id) and
        (Enum.any?(current_message.mentions, fn user ->
           user.id == Application.get_env(:siri, :bot_id)
         end) or
           current_message
           |> message_content()
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
          |> Enum.reverse()
          |> Enum.map(fn message ->
            if message.author.id == Application.get_env(:siri, :bot_id) do
              %{
                role: "assistant",
                content: "#{display_name(message)}: #{message_content(message)}"
              }
            else
              %{
                role: "user",
                content: "#{display_name(message)}: #{message_content(message)}"
              }
            end
          end)

        with {:ok, %{error: nil, object: response}} <- Siri.LLM.chat(messages) do
          Enum.each(response, fn {action, value} ->
            case action do
              "giphy" ->
                Message.create(
                  current_message.channel_id,
                  content: Siri.Substitutions.Giphy.apply_subsitition(value)
                )

              "react" ->
                Message.react(
                  current_message.channel_id,
                  current_message.id,
                  Siri.Emoji.get(value)
                )

              # all other cases where it should reply
              _ ->
                Message.create(current_message.channel_id, content: value)
            end
          end)
        else
          {:error, %{reason: reason}} ->
            Logger.error("#{reason}")
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

  @spec display_name(Nostrum.Struct.Message.t()) :: String.t()
  def display_name(message) do
    message.embeds
    |> List.wrap()
    |> Enum.find_value(fn embed -> embed.author && embed.author.name end) ||
      (message.member && message.member.nick) || message.author.username
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
end
