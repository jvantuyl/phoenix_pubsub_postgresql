defmodule Phoenix.PubSub.PostgreSQL do
  @moduledoc """
  Phoenix PubSub adapter based on PostgreSQL LISTEN / NOTIFY.

  To start it, list it in your supervision tree as:

      {Phoenix.PubSub,
       name: MyApp.PubSub,
       adapter: Phoenix.PubSub.PostgreSQL,
       repo: MyApp.Repo},

  You will also need to add `:phoenix_pubsub_postgresql` to your deps:

      defp deps do
        [{:phoenix_pubsub_postgresql, "~> 0.1"}]
      end

  ## Options

    * `:name` - The required name to register the PubSub processes, ie: `MyApp.PubSub`
    * `:repo` - An `Ecto.Repo` module to use for database connectivity
    * `:otp_app` - OTP app used to find repo configuration (usually autodetected from repo)
    * `:node_name` - Override PubSub node name (defaults to Erlang node name, then system hostname)
    * `:post_init_func` - Function executed after initialization (used for tests)

  """
  use GenServer
  @behaviour Phoenix.PubSub.Adapter

  require Logger
  alias Ecto.Adapters.SQL

  @type adapter_name :: Phoenix.PubSub.Adapter.adapter_name()
  @type node_name :: Phoenix.PubSub.node_name()
  @type message :: Phoenix.PubSub.message()
  @type topic :: Phoenix.PubSub.topic()
  @type channel :: binary()
  @type dispatcher :: Phoenix.PubSub.dispatcher()
  @type broadcast_msg :: {:broadcast, node_name(), topic(), message(), dispatcher()}
  @type notification_msg :: {:notification, pid(), reference(), channel(), binary()}

  @b85_opts [charset: :postgresql, padding: :pkcs7]
  @compression_level 6

  defmodule State do
    @type t :: %State{}

    defstruct [:name, :adapter_name, :repo]
  end

  # API
  @spec start_link(keyword()) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(opts) do
    adapter_name = Keyword.fetch!(opts, :adapter_name)

    GenServer.start_link(__MODULE__, opts, name: adapter_name)
  end

  # Phoenix.PubSub.Adapter callbacks
  @impl true
  @spec node_name(any()) :: node_name()
  def node_name(adapter_name) do
    :ets.lookup_element(adapter_name, :node_name, 2)
  end

  @impl true
  @spec broadcast(adapter_name(), topic(), message(), dispatcher()) :: :ok
  def broadcast(adapter_name, topic, message, dispatcher) do
    send(adapter_name, {:broadcast, :_, topic, message, dispatcher})

    :ok
  end

  @impl true
  @spec direct_broadcast(adapter_name(), node_name(), topic(), message(), dispatcher()) :: :ok
  def direct_broadcast(adapter_name, target_node, topic, message, dispatcher) do
    send(adapter_name, {:broadcast, target_node, topic, message, dispatcher})

    :ok
  end

  # GenServer Callbacks
  @impl true
  @spec init(keyword()) :: {:ok, State.t()}
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    adapter_name = Keyword.fetch!(opts, :adapter_name)
    repo = Keyword.fetch!(opts, :repo)
    otp_app = Keyword.get_lazy(opts, :otp_app, fn -> Application.get_application(repo) end)
    pg_config = Application.fetch_env!(otp_app, repo)

    {:ok, node_name} = find_node_name(opts)
    :ets.new(adapter_name, [:public, :named_table, read_concurrency: true])
    :ets.insert(adapter_name, {:node_name, node_name})

    main_channel = "#{name}:GLOBAL"
    node_channel = "#{name}:NODE:#{node_name}"

    {:ok, notifier_pid} = Postgrex.Notifications.start_link(pg_config)
    Logger.info("#{name}: connected to postgres")

    {:ok, _listen_ref} = Postgrex.Notifications.listen(notifier_pid, main_channel)
    Logger.info("#{name}: listening on #{main_channel}")

    {:ok, _listen_ref} = Postgrex.Notifications.listen(notifier_pid, node_channel)
    Logger.info("#{name}: listening on #{node_channel}")

    if opts[:post_init_func] do
      :ok = apply(opts[:post_init_func], [opts])
    end

    state = %State{
      name: name,
      adapter_name: adapter_name,
      repo: repo
    }

    {:ok, state}
  end

  @impl true
  @spec handle_info(broadcast_msg() | notification_msg(), State.t()) :: {:noreply, State.t()}
  def handle_info({:broadcast, target_node, topic, message, dispatcher}, state) do
    me = node_name(state.adapter_name)

    target_node
    |> case do
      :_ ->
        {:remote, "#{state.name}:GLOBAL"}

      ^me ->
        :local

      node ->
        {:remote, "#{state.name}:NODE:#{node}"}
    end
    |> case do
      {:remote, channel} ->
        raw_payload = {:phx_pgx_msg, me, topic, message, dispatcher}

        payload =
          raw_payload |> :erlang.term_to_binary(compressed: @compression_level) |> Base85.encode!(@b85_opts)

        # We use the function syntax because NOTIFY doesn't seem to parse and
        # it avoids issues casting the channel as a PostgreSQL identifier.
        {:ok, _result} = SQL.query(state.repo, "SELECT pg_notify($1, $2);", [channel, payload])

      :local ->
        # hairpin locally targeted broadcasts
        :ok = Phoenix.PubSub.local_broadcast(state.name, topic, message, dispatcher)
    end

    {:noreply, state}
  end

  def handle_info({:notification, _pid, _ref, channel, payload}, state) do
    {:phx_pgx_msg, from, topic, message, dispatcher} =
      payload |> Base85.decode!(@b85_opts) |> :erlang.binary_to_term()

    Logger.debug("#{state.name}: successfully decoded broadcast received on channel #{channel}")

    # suppress global message from self
    if from != node_name(state.adapter_name) do
      :ok = Phoenix.PubSub.local_broadcast(state.name, topic, message, dispatcher)
    end

    {:noreply, state}
  end

  # helpers
  defp find_node_name(opts) do
    if !is_nil(opts[:node_name]), do: throw(opts[:node_name])
    if Node.alive?(), do: throw(node())
    # per the docs, this call never fails
    {:ok, inet_hostname} = :inet.gethostname()
    throw(inet_hostname)
  catch
    new_node_name ->
      {:ok, new_node_name}
  end
end
