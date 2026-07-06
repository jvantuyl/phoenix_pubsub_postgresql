# Phoenix.PubSub.PostgreSQL

[![Build Status](https://github.com/jvantuyl/phoenix_pubsub_postgresql/workflows/CI/badge.svg)](https://github.com/jvantuyl/phoenix_pubsub_postgresql/actions/workflows/ci.yml) [![Hex.pm](https://img.shields.io/hexpm/v/phoenix_pubsub_postgresql.svg)](https://hex.pm/packages/phoenix_pubsub_postgresql) [![Documentation](https://img.shields.io/badge/documentation-gray)](https://phoenix-pubsub-postgresql.hexdocs.pm)

A Phoenix PubSub adapter that uses PostgreSQL's `LISTEN` / `NOTIFY` for message distribution.

This adapter allows multiple nodes of a Phoenix application to communicate through a shared PostgreSQL database, eliminating the need for additional infrastructure like Redis or a distributed Erlang cluster.

## Features

- Uses PostgreSQL's native `LISTEN` / `NOTIFY` mechanism
- Compresses and encodes messages using Base85 for efficient transmission
- Supports both broadcast and direct node-to-node messaging
- Automatic node name detection (uses Erlang node name or system hostname)

## Installation

Add `phoenix_pubsub_postgresql` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:phoenix_pubsub_postgresql, "~> 0.6.0"}
  ]
end
```

Documentation is generated with [ExDoc](https://github.com/elixir-lang/ex_doc) and published on [HexDocs](https://hexdocs.pm). The docs can be found at [https://phoenix-pubsub-postgresql.hexdocs.pm](https://phoenix-pubsub-postgresql.hexdocs.pm).

## Configuration

Add the PubSub adapter to your application's supervision tree:

```elixir
children = [
  MyApp.Repo,
  {Phoenix.PubSub,
   name: MyApp.PubSub,
   adapter: Phoenix.PubSub.PostgreSQL,
   repo: MyApp.Repo}
]
```

### Options

- `:name` - (required) The name to register the PubSub processes, e.g., `MyApp.PubSub`
- `:repo` - (required) An `Ecto.Repo` module to use for database connectivity
- `:otp_app` - OTP app used to find repo configuration (usually autodetected from repo)
- `:node_name` - Override PubSub node name (defaults to Erlang node name, then system hostname)
- `:pg_config` - Override PostgreSQL configuration options. See https://postgrex.hexdocs.pm/Postgrex.Notifications.html#start_link/1
  for available options

## Usage

Once configured, you can use Phoenix.PubSub as normal:

```elixir
# Subscribe to a topic
Phoenix.PubSub.subscribe(MyApp.PubSub, "my_topic")

# Broadcast a message
Phoenix.PubSub.broadcast(MyApp.PubSub, "my_topic", {:some, "message"})
```

## How It Works

The adapter creates two PostgreSQL notification channels:

1. A global channel (`{name}:GLOBAL`) for broadcasts to all nodes
2. A node-specific channel (`{name}:NODE:{node_name}`) for direct messages

Messages are serialized using Erlang's term format, compressed, and encoded with Base85 to fit within PostgreSQL's NOTIFY payload limits.
