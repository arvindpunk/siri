import Config

config :siri,
  bot_id: System.fetch_env!("BOT_ID") |> String.to_integer(),
  bot_name: System.fetch_env!("BOT_NAME"),
  bot_token: System.fetch_env!("BOT_TOKEN"),
  google_api_key: System.fetch_env!("GOOGLE_API_KEY")
