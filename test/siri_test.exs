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
end
