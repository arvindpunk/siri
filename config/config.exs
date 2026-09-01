import Config

config :nostrum,
  youtubedl: nil,
  streamlink: nil

config :siri, ecto_repos: [Siri.Repo]

config :siri, Siri.Repo,
  database: "ecto_simple",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: "5432"
