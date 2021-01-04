defmodule Phoenix.PubSub.PostgreSQL.MixProject do
  use Mix.Project

  def project do
    [
      app: :phoenix_pubsub_postgresql,
      version: "0.1.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:base85, ">= 0.2.0"},
      {:ecto, ">= 3.0.0"},
      {:ecto_sql, ">= 3.0.0"},
      {:phoenix_pubsub, ">= 2.0.0"},
      {:postgrex, ">= 0.0.0"},
      # docs
      {:ex_doc, "~> 0.23", only: :dev, runtime: false}
    ]
  end
end
