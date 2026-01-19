defmodule Testing.Repo do
  use Ecto.Repo,
    otp_app: :phoenix_pubsub_postgresql,
    adapter: Ecto.Adapters.Postgres
end
