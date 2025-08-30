defmodule Siri.Repo do
  use Ecto.Repo,
    otp_app: :siri,
    adapter: Ecto.Adapters.Postgres
end
