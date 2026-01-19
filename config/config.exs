import Config

config :phoenix_pubsub_postgresql, ecto_repos: [Testing.Repo]

if config_env() == :test do
  import_config "test.exs"
end
