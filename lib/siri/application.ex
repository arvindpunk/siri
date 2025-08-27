defmodule Siri.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  require Logger

  use Application

  @impl true
  def start(_type, _args) do
    bot_options = %{
      name: Siri,
      consumer: Siri.Consumer,
      intents: [:guild_messages, :message_content],
      wrapped_token: fn -> System.fetch_env!("BOT_TOKEN") end
    }

    children = [
      {Nostrum.Bot, bot_options}
    ]

    opts = [strategy: :one_for_one, name: Siri.Supervisor]
    Logger.info(children)
    Supervisor.start_link(children, opts)
  end
end
