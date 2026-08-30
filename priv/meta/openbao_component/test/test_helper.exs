ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(NewApiApp.Repo, :manual)

# NewApiApp.Vault.LiveApproleTest exercises the real sidecar rather than a
# mock, so it's excluded by default -- opt in with `mix test --include
# openbao`. Merges onto whatever `:exclude` another plugin's own contributed
# block already set here -- a plain `ExUnit.configure(exclude: [openbao:
# true])` would overwrite it outright, since ExUnit.configure/1 replaces the
# option rather than merging it.
ExUnit.configure(exclude: [{:openbao, true} | Keyword.get(ExUnit.configuration(), :exclude, [])])
