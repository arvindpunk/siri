import Config

config :siri,
  bot_id: System.fetch_env!("BOT_ID"),
  bot_token: System.fetch_env!("BOT_TOKEN"),
  google_api_key: System.fetch_env!("GOOGLE_API_KEY")
