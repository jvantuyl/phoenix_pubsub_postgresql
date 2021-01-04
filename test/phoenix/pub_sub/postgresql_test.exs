pif = fn opts ->
  Ecto.Adapters.SQL.Sandbox.checkout(opts[:repo])
end

Application.put_env(
  :phoenix_pubsub,
  :test_adapter,
  {Phoenix.PubSub.PostgreSQL,
   name: Testing.PubSub, repo: Testing.Repo, node_name: :pubsub_test, post_init_func: pif}
)

Code.require_file("#{Mix.Project.deps_paths()[:phoenix_pubsub]}/test/shared/pubsub_test.exs")
