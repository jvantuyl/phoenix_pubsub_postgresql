defmodule Phoenix.PubSub.PostgreSQLTest do
  use ExUnit.Case, async: false

  alias Phoenix.PubSub
  alias Phoenix.PubSub.PostgreSQL

  require Logger

  @moduletag :capture_log

  setup_all do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Testing.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Testing.Repo, {:shared, self()})

    pubsub_name = :"test_pubsub_#{System.unique_integer([:positive])}"
    node_name = :"test_node_#{System.unique_integer([:positive])}"

    pid =
      start_link_supervised!(
        {PubSub, name: pubsub_name, adapter: PostgreSQL, repo: Testing.Repo, node_name: node_name}
      )

    # Give the adapter time to connect and set up listeners
    Process.sleep(100)

    Logger.info("Started pubsub #{pubsub_name}@#{node_name} (#{inspect(pid)})")

    {:ok, pubsub: pubsub_name, node: node_name, pid: pid}
  end

  describe "node_name/1" do
    test "returns the configured node name", %{pubsub: pubsub} do
      adapter_name = Module.concat(pubsub, Adapter)
      node_name = PostgreSQL.node_name(adapter_name)
      assert is_atom(node_name)
      assert to_string(node_name) =~ "test_node_"
    end
  end

  describe "subscribe and broadcast" do
    test "receives broadcasted messages", %{pubsub: pubsub} do
      topic = "test:topic:#{System.unique_integer()}"

      :ok = PubSub.subscribe(pubsub, topic)
      :ok = PubSub.broadcast(pubsub, topic, {:hello, "world"})

      assert_receive {:hello, "world"}, 1000
    end

    test "does not receive messages from unsubscribed topics", %{pubsub: pubsub} do
      topic1 = "test:topic1:#{System.unique_integer()}"
      topic2 = "test:topic2:#{System.unique_integer()}"

      :ok = PubSub.subscribe(pubsub, topic1)
      :ok = PubSub.broadcast(pubsub, topic2, {:hello, "world"})

      refute_receive {:hello, "world"}, 200
    end

    test "unsubscribe stops receiving messages", %{pubsub: pubsub} do
      topic = "test:topic:#{System.unique_integer()}"

      :ok = PubSub.subscribe(pubsub, topic)
      :ok = PubSub.broadcast(pubsub, topic, {:hello, "world"})

      assert_receive {:hello, "world"}, 200

      :ok = PubSub.unsubscribe(pubsub, topic)
      :ok = PubSub.broadcast(pubsub, topic, {:hello, "world"})

      refute_receive {:hello, "world"}, 200
    end

    test "multiple subscribers receive the same message", %{pubsub: pubsub} do
      topic = "test:topic:#{System.unique_integer()}"
      parent = self()

      # Spawn subscriber processes
      pids =
        for i <- 1..3 do
          spawn_link(fn ->
            :ok = PubSub.subscribe(pubsub, topic)
            send(parent, {:subscribed, i})

            receive do
              msg -> send(parent, {:received, i, msg})
            end
          end)
        end

      # Wait for all to subscribe
      for i <- 1..3 do
        assert_receive {:subscribed, ^i}, 1000
      end

      # Broadcast
      :ok = PubSub.broadcast(pubsub, topic, :test_message)

      # All should receive
      for i <- 1..3 do
        assert_receive {:received, ^i, :test_message}, 1000
      end

      # Clean up
      Enum.each(pids, &Process.exit(&1, :normal))

      # give it a bit of time to exit
      :timer.sleep(100)
    end
  end

  describe "broadcast_from" do
    test "sender does not receive their own broadcast_from message", %{pubsub: pubsub} do
      topic = "test:topic:#{System.unique_integer()}"

      :ok = PubSub.subscribe(pubsub, topic)
      :ok = PubSub.broadcast_from(pubsub, self(), topic, {:hello, "world"})

      refute_receive {:hello, "world"}, 200
    end

    test "other subscribers receive broadcast_from messages", %{pubsub: pubsub} do
      topic = "test:topic:#{System.unique_integer()}"
      parent = self()

      subscriber =
        spawn_link(fn ->
          :ok = PubSub.subscribe(pubsub, topic)
          send(parent, :subscribed)

          receive do
            msg -> send(parent, {:received, msg})
          end
        end)

      assert_receive :subscribed, 1000

      :ok = PubSub.broadcast_from(pubsub, self(), topic, {:hello, "world"})

      assert_receive {:received, {:hello, "world"}}, 1000

      Process.exit(subscriber, :normal)

      # give it a bit of time to exit
      :timer.sleep(100)
    end
  end

  describe "direct_broadcast" do
    test "sends message to specific node (self)", %{pubsub: pubsub, node: node_name} do
      topic = "test:topic:#{System.unique_integer()}"

      :ok = PubSub.subscribe(pubsub, topic)
      :ok = PubSub.direct_broadcast(node_name, pubsub, topic, {:direct, "message"})

      assert_receive {:direct, "message"}, 1000
    end
  end

  describe "message encoding" do
    test "handles various Elixir terms", %{pubsub: pubsub} do
      topic = "test:topic:#{System.unique_integer()}"
      :ok = PubSub.subscribe(pubsub, topic)

      messages = [
        :atom,
        "string",
        123,
        3.14,
        [1, 2, 3],
        %{key: "value"},
        {:tuple, "with", :elements},
        %{nested: %{map: [1, 2, %{deep: :value}]}}
      ]

      for msg <- messages do
        :ok = PubSub.broadcast(pubsub, topic, msg)
        assert_receive ^msg, 1000
      end
    end

    test "handles large messages", %{pubsub: pubsub} do
      topic = "test:topic:#{System.unique_integer()}"
      :ok = PubSub.subscribe(pubsub, topic)

      large_data = %{
        data: String.duplicate("x", 5000),
        list: Enum.to_list(1..100)
      }

      :ok = PubSub.broadcast(pubsub, topic, large_data)
      assert_receive ^large_data, 2000
    end
  end

  describe "multiple pubsub instances" do
    test "separate pubsub instances are isolated", %{pubsub: pubsub1} do
      # Start a second pubsub
      pubsub2 = :"test_pubsub2_#{System.unique_integer([:positive])}"

      p2_pid =
        start_link_supervised!(
          {PubSub,
           name: pubsub2,
           adapter: PostgreSQL,
           repo: Testing.Repo,
           node_name: :"test_node2_#{System.unique_integer([:positive])}"},
          id: :pubsub2
        )

      Process.sleep(100)

      topic = "shared:topic:#{System.unique_integer()}"

      :ok = PubSub.subscribe(pubsub1, topic)
      :ok = PubSub.broadcast(pubsub2, topic, :from_pubsub2)

      # Should not receive - different pubsub instances
      refute_receive :from_pubsub2, 300

      # shut it down
      Supervisor.stop(p2_pid)

      :ok
    end
  end
end
