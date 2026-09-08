defmodule Siri.ChannelHandler do
  @moduledoc false
  use GenServer

  alias Nostrum.Api.{Message, Channel}

  require Logger

  @history_limit 1_000
  @context_limit 75
  @summary_usage "try `siri summarize 100`, `siri summarize 30m`, or `give me the gist of this conversation`"

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

    if should_respond, do: respond(current_message, state.messages)

    state =
      if length(state.messages) > @history_limit,
        do: %{state | messages: Enum.take(state.messages, @history_limit)},
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
    Siri.LLM.chat(
      [
        %{role: "system", content: Siri.Prompt.system_prompt()}
        | messages
      ],
      response_model: Siri.Model,
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

  defp respond(current_message, state_messages) do
    Task.async(fn ->
      Channel.start_typing(current_message.channel_id)
    end)

    Task.async(fn ->
      messages =
        state_messages
        |> Enum.take(@context_limit)
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

          :summarize ->
            summarize(current_message, state_messages, response)

          _ ->
            Message.create(current_message.channel_id,
              content:
                "this is a placeholder message where the LLM didn't want to reply to you as the message wasn't worth replying, you twat. (here for debugging purposes)"
            )
        end
      else
        {:error, msg} ->
          Logger.error("error: #{inspect(msg)}")
      end
    end)
  end

  defp summarize(current_message, state_messages, response) do
    Task.async(fn ->
      Channel.start_typing(current_message.channel_id)
    end)

    Task.async(fn ->
      with {:ok, request, cap_notice} <- Siri.Summarizer.request_from_response(response) do
        selection =
          Siri.Summarizer.select_with_history(
            state_messages,
            request,
            current_message.id,
            now: message_timestamp(current_message),
            fetch_messages: &fetch_older_messages(current_message.channel_id, &1, &2)
          )

        summarize_selection(current_message.channel_id, selection, cap_notice)
      else
        {:error, :invalid_request} ->
          Message.create(current_message.channel_id, content: @summary_usage)
      end
    end)
  end

  defp summarize_selection(channel_id, %{messages: []}, _cap_notice) do
    Message.create(channel_id, content: "there aren't any messages available to summarize yet")
  end

  defp summarize_selection(channel_id, selection, cap_notice) do
    case Siri.Summarizer.summarize(selection.messages) do
      {:ok, summary} ->
        [cap_notice, partial_history_notice(selection), summary]
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n\n")
        |> Siri.Summarizer.split_for_discord()
        |> Enum.each(fn chunk ->
          Message.create(channel_id, content: chunk)
        end)

      {:error, reason} ->
        Logger.error("summary error: #{inspect(reason)}")

        Message.create(channel_id,
          content: "couldn't summarize that right now, try again in a bit"
        )
    end
  end

  defp partial_history_notice(%{history_error: nil}), do: nil

  defp partial_history_notice(_selection) do
    "i couldn't retrieve older channel history, so this only covers the messages currently available"
  end

  defp fetch_older_messages(channel_id, before_id, limit) do
    Channel.messages(channel_id, limit, {:before, before_id})
  rescue
    error -> {:error, error}
  end

  defp message_timestamp(%{timestamp: %DateTime{} = timestamp}), do: timestamp

  defp message_timestamp(%{timestamp: %NaiveDateTime{} = timestamp}) do
    DateTime.from_naive!(timestamp, "Etc/UTC")
  end

  defp message_timestamp(_message), do: DateTime.utc_now()
end
