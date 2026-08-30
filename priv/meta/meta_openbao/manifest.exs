%{
  deps: [],
  files: [
    {"lib/APP/vault.ex", :sole_owner},
    {"lib/APP/vault/auth.ex", :sole_owner},
    {"test/APP/vault/auth_test.exs", :sole_owner},
    {"test/APP/vault_test.exs", :sole_owner},
    {"README.md", :contributes, [key: :openbao_readme]},
    {"compose.yaml", :contributes, [key: :openbao_compose]},
    {"config/dev.exs", :contributes, [key: :openbao_dev]},
    {"config/runtime.exs", :contributes, [key: :openbao_runtime, at: {:env, :prod}]},
    {"config/test.exs", :contributes, [key: :openbao_test]},
    {"lib/APP/application.ex", :manual,
     [
       after: ["  @impl true", "  def start(_type, _args) do", "    children = ["],
       key: :openbao_application
     ]}
  ],
  name: :openbao,
  version: "0.1.0"
}
