ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(NewApiApp.Repo, :manual)

# Redix has no official test/stub tooling, so NewApiApp.ValkeyTest exercises
# the real sidecar and is excluded by default -- opt in with
# `mix test --include valkey`.
ExUnit.configure(exclude: [valkey: true])
