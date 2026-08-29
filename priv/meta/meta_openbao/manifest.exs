%{
  deps: [],
  files: [
    {"lib/APP/vault.ex", :sole_owner},
    {"test/APP/vault_test.exs", :sole_owner},
    {"README.md", :contributes, [key: :openbao_readme]},
    {"compose.yaml", :contributes, [key: :openbao_compose]},
    {"config/dev.exs", :contributes, [key: :openbao_dev]},
    {"config/runtime.exs", :contributes, [key: :openbao_runtime, at: {:env, :prod}]},
    {"config/test.exs", :contributes, [key: :openbao_test]}
  ],
  name: :openbao,
  version: "0.1.0"
}
