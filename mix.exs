defmodule Phoenix.PubSub.PostgreSQL.MixProject do
  use Mix.Project

  @version "0.5.0"
  @source_url "https://github.com/jvantuyl/phoenix_pubsub_postgresql"

  def project do
    [
      app: :phoenix_pubsub_postgresql,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      deps: deps(),
      # Hex Packaging
      package: package(),
      # Docs
      name: "Phoenix.PubSub.PostgreSQL",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: &docs/0
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      test: ["ecto.create --quiet", "test"]
    ]
  end

  defp description do
    "A Phoenix PubSub adapter using PostgreSQL LISTEN/NOTIFY for message distribution."
  end

  defp package do
    [
      description: description(),
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE.md),
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE.md"],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:base85, "~> 1.0"},
      {:ecto, ">= 3.0.0"},
      {:ecto_sql, ">= 3.0.0"},
      {:phoenix_pubsub, ">= 2.0.0"},
      {:postgrex, ">= 0.0.0"},
      # docs
      {:ex_doc, "~> 0.23", only: :dev, runtime: false}
    ]
  end
end
