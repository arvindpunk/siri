defmodule Siri.Summarizer do
  @moduledoc false

  @default_session_limit 75
  @max_summary_messages 200
  @max_duration_minutes 30
  @session_gap_seconds 60
  @discord_message_limit 2_000

  @type request :: :session | {:count, pos_integer()} | {:duration, pos_integer()}

  @type selection :: %{
          messages: list(Nostrum.Struct.Message.t()),
          fetched?: boolean(),
          incomplete?: boolean(),
          history_error: term() | nil
        }

  @spec request_from_response(map()) ::
          {:ok, request(), String.t() | nil} | {:error, :invalid_request}
  def request_from_response(response) do
    case Map.get(response, :summary_scope) do
      :session ->
        {:ok, :session, nil}

      :count ->
        normalize_amount(Map.get(response, :summary_amount), @max_summary_messages, "messages")
        |> to_request(:count)

      :duration ->
        normalize_amount(Map.get(response, :summary_amount), @max_duration_minutes, "minutes")
        |> to_request(:duration)

      _ ->
        {:error, :invalid_request}
    end
  end

  @spec select_messages(list(), request(), integer(), DateTime.t()) :: list()
  def select_messages(messages, request, command_message_id, now \\ DateTime.utc_now()) do
    messages
    |> prepare_messages(command_message_id)
    |> select_newest_first(request, now)
    |> then(fn {selected, _needs_more?} -> Enum.reverse(selected) end)
  end

  @spec select_with_history(list(), request(), integer(), keyword()) :: selection()
  def select_with_history(messages, request, command_message_id, options) do
    now = Keyword.get(options, :now, DateTime.utc_now())
    fetch_messages = Keyword.get(options, :fetch_messages)
    all_messages = normalize_messages(messages)
    prepared_messages = eligible_messages(all_messages, command_message_id)
    {selected, needs_more?} = select_newest_first(prepared_messages, request, now)

    result = %{
      messages: Enum.reverse(selected),
      fetched?: false,
      incomplete?: needs_more?,
      history_error: nil
    }

    if needs_more? and is_function(fetch_messages, 2) do
      fetch_missing_history(
        result,
        all_messages,
        request,
        command_message_id,
        now,
        fetch_messages
      )
    else
      result
    end
  end

  @spec format_history(list()) :: String.t()
  def format_history(messages) do
    Enum.map_join(messages, "\n\n", fn message ->
      "[#{format_timestamp(message.timestamp)}] #{display_name(message)}:\n#{Siri.ChannelHandler.message_content(message)}"
    end)
  end

  @spec summarize(list()) :: {:ok, String.t()} | {:error, any()}
  def summarize(messages) do
    history = format_history(messages)

    Siri.LLM.chat(
      [
        %{role: "system", content: Siri.SummaryPrompt.system_prompt()},
        %{role: "user", content: history}
      ],
      response_model: Siri.SummaryModel,
      max_retries: 0
    )
    |> case do
      {:ok, %{summary: summary}} when is_binary(summary) and summary != "" -> {:ok, summary}
      {:ok, response} -> {:error, {:invalid_response, response}}
      error -> error
    end
  end

  @spec split_for_discord(String.t(), pos_integer()) :: [String.t()]
  def split_for_discord(text, limit \\ @discord_message_limit) do
    text
    |> String.trim()
    |> split_text(limit, [])
    |> Enum.reverse()
  end

  defp fetch_missing_history(
         result,
         all_messages,
         request,
         command_message_id,
         now,
         fetch_messages
       ) do
    with before_id when not is_nil(before_id) <- oldest_message_id(all_messages),
         limit when limit > 0 <- fetch_limit(request, result.messages),
         {:ok, fetched_messages} when is_list(fetched_messages) <-
           fetch_messages.(before_id, limit) do
      combined_messages = normalize_messages(all_messages ++ fetched_messages)

      eligible_messages = eligible_messages(combined_messages, command_message_id)
      {selected, needs_more?} = select_newest_first(eligible_messages, request, now)

      %{
        messages: Enum.reverse(selected),
        fetched?: true,
        incomplete?: needs_more?,
        history_error: nil
      }
    else
      {:error, reason} -> %{result | history_error: reason, incomplete?: true}
      _ -> result
    end
  end

  defp normalize_amount(amount, limit, label) when is_integer(amount) and amount > 0 do
    capped_amount = min(amount, limit)

    notice =
      if amount > limit do
        "using the maximum of #{limit} #{label} for this summary"
      end

    {:ok, capped_amount, notice}
  end

  defp normalize_amount(_, _limit, _label), do: {:error, :invalid_request}

  defp to_request({:ok, amount, notice}, scope), do: {:ok, {scope, amount}, notice}
  defp to_request(error, _scope), do: error

  defp prepare_messages(messages, command_message_id) do
    messages
    |> normalize_messages()
    |> eligible_messages(command_message_id)
  end

  defp eligible_messages(messages, command_message_id) do
    Enum.reject(messages, fn message ->
      message.id == command_message_id or Siri.ChannelHandler.message_content(message) == ""
    end)
  end

  defp normalize_messages(messages) do
    messages
    |> deduplicate_messages()
    |> Enum.sort_by(&message_sort_key/1, :desc)
  end

  defp deduplicate_messages(messages) do
    messages
    |> Enum.reduce(%{}, fn message, unique_messages ->
      Map.put_new(unique_messages, message.id, message)
    end)
    |> Map.values()
  end

  defp message_sort_key(message) do
    case to_datetime(message.timestamp) do
      %DateTime{} = timestamp -> {DateTime.to_unix(timestamp, :microsecond), message.id}
      nil -> {0, message.id}
    end
  end

  defp select_newest_first(messages, :session, _now), do: session_selection(messages)

  defp select_newest_first(messages, {:count, count}, _now) do
    count = min(count, @max_summary_messages)
    selected = Enum.take(messages, count)
    {selected, length(selected) < count}
  end

  defp select_newest_first(messages, {:duration, minutes}, now) do
    minutes = min(minutes, @max_duration_minutes)
    cutoff = DateTime.add(now, -minutes * 60, :second)

    selected =
      messages
      |> Enum.filter(&on_or_after?(&1.timestamp, cutoff))
      |> Enum.take(@max_summary_messages)

    oldest_message = List.last(messages)

    needs_more? =
      cond do
        messages == [] ->
          true

        length(selected) == @max_summary_messages ->
          false

        match?(%DateTime{}, to_datetime(oldest_message.timestamp)) ->
          DateTime.compare(to_datetime(oldest_message.timestamp), cutoff) == :gt

        true ->
          false
      end

    {selected, needs_more?}
  end

  defp session_selection([]), do: {[], true}

  defp session_selection([first_message | remaining_messages]) do
    {selected, boundary_found?} =
      Enum.reduce_while(remaining_messages, {[first_message], false}, fn message,
                                                                         {selected,
                                                                          _boundary_found?} ->
        previous_message = List.last(selected)

        cond do
          length(selected) >= @default_session_limit ->
            {:halt, {selected, true}}

          gap_exceeds_session_limit?(previous_message, message) ->
            {:halt, {selected, true}}

          true ->
            {:cont, {selected ++ [message], false}}
        end
      end)

    {selected, not boundary_found? and length(selected) < @default_session_limit}
  end

  defp gap_exceeds_session_limit?(newer_message, older_message) do
    with %DateTime{} = newer <- to_datetime(newer_message.timestamp),
         %DateTime{} = older <- to_datetime(older_message.timestamp) do
      DateTime.diff(newer, older, :second) > @session_gap_seconds
    else
      _ -> true
    end
  end

  defp fetch_limit(:session, selected_messages),
    do: max(@default_session_limit - length(selected_messages), 0)

  defp fetch_limit({:count, count}, selected_messages),
    do: max(min(count, @max_summary_messages) - length(selected_messages), 0)

  defp fetch_limit({:duration, _minutes}, selected_messages),
    do: max(@max_summary_messages - length(selected_messages), 0)

  defp oldest_message_id([]), do: nil
  defp oldest_message_id(messages), do: messages |> List.last() |> Map.get(:id)

  defp on_or_after?(timestamp, cutoff) do
    case to_datetime(timestamp) do
      %DateTime{} = datetime -> DateTime.compare(datetime, cutoff) in [:eq, :gt]
      nil -> false
    end
  end

  defp to_datetime(%DateTime{} = timestamp), do: timestamp
  defp to_datetime(%NaiveDateTime{} = timestamp), do: DateTime.from_naive!(timestamp, "Etc/UTC")
  defp to_datetime(_timestamp), do: nil

  defp format_timestamp(timestamp) do
    case to_datetime(timestamp) do
      %DateTime{} = datetime -> Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
      nil -> "unknown time"
    end
  end

  defp display_name(message) do
    Enum.find_value(List.wrap(message.embeds), fn embed -> embed.author && embed.author.name end) ||
      (message.member && message.member.nick) || message.author.username
  end

  defp split_text("", _limit, chunks), do: chunks

  defp split_text(text, limit, chunks) do
    if String.length(text) <= limit do
      [text | chunks]
    else
      {candidate, rest} = String.split_at(text, limit)
      {chunk, remainder} = split_at_whitespace(candidate, rest)
      split_text(remainder, limit, [chunk | chunks])
    end
  end

  defp split_at_whitespace(candidate, rest) do
    case :binary.matches(candidate, ["\n", " "]) |> List.last() do
      {position, separator_length} when position > 0 ->
        chunk = binary_part(candidate, 0, position) |> String.trim_trailing()

        candidate_remainder =
          binary_part(
            candidate,
            position + separator_length,
            byte_size(candidate) - position - separator_length
          )

        {chunk, String.trim_leading(candidate_remainder <> rest)}

      _ ->
        {candidate, rest}
    end
  end
end
