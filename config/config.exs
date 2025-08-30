import Config

config :nostrum,
  youtubedl: nil,
  streamlink: nil

config :iex, auto_reload: true

config :siri, ecto_repos: [Siri.Repo]

config :siri, Siri.Repo,
  database: "ecto_simple",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: "5432"
