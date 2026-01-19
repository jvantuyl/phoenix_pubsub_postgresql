# Start the repo for testing
{:ok, _} = Testing.Repo.start_link()

ExUnit.start(assert_receive_timeout: 5_000)
Ecto.Adapters.SQL.Sandbox.mode(Testing.Repo, :manual)
