ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(NewApiApp.Repo, :manual)

# NewApiApp.Vault.LiveApproleTest exercises the real sidecar rather than a
# mock, so it's excluded by default -- opt in with `mix test --include
# openbao`.
ExUnit.configure(exclude: [openbao: true])
