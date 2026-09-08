defmodule SiriTest do
  use ExUnit.Case
  doctest Siri

  test "greets the world" do
    assert Siri.hello() == :world
  end

  test "reads text from Discord embeds" do
    message = %Nostrum.Struct.Message{
      content: "message text",
      embeds: [
        %Nostrum.Struct.Embed{
          title: "Build status",
          description: "The build failed",
          fields: [
            %Nostrum.Struct.Embed.Field{name: "Branch", value: "main"}
          ]
        }
      ]
    }

    expected = "message text\nBuild status\nThe build failed\nBranch: main"

    assert Siri.ChannelHandler.message_content(message) == expected
  end

  test "reads embed-only messages" do
    message = %Nostrum.Struct.Message{
      content: "",
      embeds: [%Nostrum.Struct.Embed{description: "embed text"}]
    }

    assert Siri.ChannelHandler.message_content(message) == "embed text"
  end

  describe "summary requests selected by the response model" do
    test "normalizes session, count, and duration requests" do
      assert Siri.Summarizer.request_from_response(%{summary_scope: :session}) ==
               {:ok, :session, nil}

      assert Siri.Summarizer.request_from_response(%{
               summary_scope: :count,
               summary_amount: 100
             }) == {:ok, {:count, 100}, nil}

      assert Siri.Summarizer.request_from_response(%{
               summary_scope: :duration,
               summary_amount: 30
             }) == {:ok, {:duration, 30}, nil}
    end

    test "caps count and duration requests" do
      assert Siri.Summarizer.request_from_response(%{
               summary_scope: :count,
               summary_amount: 500
             }) == {:ok, {:count, 200}, "using the maximum of 200 messages for this summary"}

      assert Siri.Summarizer.request_from_response(%{
               summary_scope: :duration,
               summary_amount: 45
             }) == {:ok, {:duration, 30}, "using the maximum of 30 minutes for this summary"}
    end

    test "rejects a summary response with an invalid scope or amount" do
      assert Siri.Summarizer.request_from_response(%{summary_scope: :count}) ==
               {:error, :invalid_request}

      assert Siri.Summarizer.request_from_response(%{
               summary_scope: :duration,
               summary_amount: 0
             }) == {:error, :invalid_request}
    end
  end

  describe "summary message selection" do
    test "removes the command, selects newest messages, and returns them chronologically" do
      messages = [
        message(4, "siri summarize 2", ~U[2026-09-08 13:04:00Z]),
        message(3, "newest", ~U[2026-09-08 13:03:00Z]),
        message(2, "middle", ~U[2026-09-08 13:02:00Z]),
        message(1, "oldest", ~U[2026-09-08 13:01:00Z])
      ]

      selected = Siri.Summarizer.select_messages(messages, {:count, 2}, 4)

      assert Enum.map(selected, & &1.id) == [2, 3]
    end

    test "never selects more than 200 messages" do
      messages =
        for id <- 300..1//-1 do
          message(id, "message #{id}", ~U[2026-09-08 13:00:00Z])
        end

      selected = Siri.Summarizer.select_messages(messages, {:count, 5_000}, -1)

      assert length(selected) == 200
      assert hd(selected).id == 101
      assert List.last(selected).id == 300
    end

    test "filters by the 30-minute cutoff and returns messages chronologically" do
      messages = [
        message(4, "siri summarize 30m", ~U[2026-09-08 13:00:00Z]),
        message(3, "recent", ~U[2026-09-08 12:30:00Z]),
        message(2, "at cutoff", ~U[2026-09-08 12:30:00Z]),
        message(1, "too old", ~U[2026-09-08 12:29:59Z])
      ]

      selected =
        Siri.Summarizer.select_messages(
          messages,
          {:duration, 30},
          4,
          ~U[2026-09-08 13:00:00Z]
        )

      assert Enum.map(selected, & &1.id) == [2, 3]
    end

    test "uses the newest contiguous session with a one-minute inactivity gap" do
      messages = [
        message(6, "give me the gist", ~U[2026-09-08 13:12:00Z]),
        message(5, "latest", ~U[2026-09-08 13:11:00Z]),
        message(4, "still talking", ~U[2026-09-08 13:10:00Z]),
        message(3, "same session", ~U[2026-09-08 13:09:00Z]),
        message(2, "previous session", ~U[2026-09-08 13:07:59Z])
      ]

      selected = Siri.Summarizer.select_messages(messages, :session, 6)

      assert Enum.map(selected, & &1.id) == [3, 4, 5]
    end

    test "fetches only missing older messages and deduplicates them" do
      messages = [
        message(5, "summarize the last 4 messages", ~U[2026-09-08 13:04:00Z]),
        message(4, "newest", ~U[2026-09-08 13:03:00Z]),
        message(3, "middle", ~U[2026-09-08 13:02:00Z])
      ]

      selection =
        Siri.Summarizer.select_with_history(messages, {:count, 4}, 5,
          fetch_messages: fn before_id, limit ->
            assert before_id == 3
            assert limit == 2

            {:ok,
             [
               message(3, "middle", ~U[2026-09-08 13:02:00Z]),
               message(2, "older", ~U[2026-09-08 13:01:00Z]),
               message(1, "oldest", ~U[2026-09-08 13:00:00Z])
             ]}
          end
        )

      assert selection.fetched?
      refute selection.incomplete?
      assert Enum.map(selection.messages, & &1.id) == [1, 2, 3, 4]
    end

    test "keeps available messages when Discord history retrieval fails" do
      messages = [
        message(3, "summarize the last 3", ~U[2026-09-08 13:02:00Z]),
        message(2, "available", ~U[2026-09-08 13:01:00Z])
      ]

      selection =
        Siri.Summarizer.select_with_history(messages, {:count, 3}, 3,
          fetch_messages: fn _before_id, _limit -> {:error, :missing_permissions} end
        )

      assert selection.incomplete?
      assert selection.history_error == :missing_permissions
      assert Enum.map(selection.messages, & &1.id) == [2]
    end
  end

  test "formats author, timestamp, URLs, and embed content for the summarizer" do
    message = %Nostrum.Struct.Message{
      id: 1,
      author: %Nostrum.Struct.User{username: "harsh"},
      content: "details: https://example.com/incident",
      embeds: [%Nostrum.Struct.Embed{description: "production incident"}],
      timestamp: ~U[2026-09-08 13:04:00Z]
    }

    assert Siri.Summarizer.format_history([message]) ==
             "[2026-09-08 13:04] harsh:\ndetails: https://example.com/incident\nproduction incident"
  end

  test "splits long summaries without exceeding Discord's message limit" do
    chunks = Siri.Summarizer.split_for_discord(String.duplicate("word ", 1_000), 100)

    assert length(chunks) > 1
    assert Enum.all?(chunks, &(String.length(&1) <= 100))
    assert Enum.all?(chunks, &(&1 != ""))
  end

  defp message(id, content, timestamp) do
    %Nostrum.Struct.Message{
      id: id,
      content: content,
      embeds: [],
      timestamp: timestamp
    }
  end
end
