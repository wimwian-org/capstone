ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(NewApiApp.Repo, :manual)

# NewApiApp.Valkey.CacheLiveTest exercises the real sidecar rather than a
# mock, so it's excluded by default -- opt in with `mix test --include
# valkey`.
ExUnit.configure(exclude: [valkey: true])
