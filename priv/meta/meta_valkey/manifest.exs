%{
  deps: [
    "{:nebulex, \"~> 3.0\"}",
    "{:nebulex_local, \"~> 3.0\"}",
    "{:nebulex_redis_adapter, \"~> 3.0\"}",
    "{:redix, \"~> 1.8\"}"
  ],
  files: [
    {"lib/APP/valkey.ex", :sole_owner},
    {"test/APP/valkey_test.exs", :sole_owner},
    {"README.md", :contributes, [key: :valkey_readme]},
    {"compose.yaml", :contributes, [key: :valkey_compose]},
    {"config/dev.exs", :contributes, [key: :valkey_dev]},
    {"config/runtime.exs", :contributes, [key: :valkey_runtime, at: {:env, :prod}]},
    {"config/test.exs", :contributes, [key: :valkey_test]},
    {"lib/APP/application.ex", :contributes,
     [key: :valkey_application, child: "<%= @module %>.Valkey"]},
    {"test/test_helper.exs", :contributes, [key: :valkey_test_helper]}
  ],
  name: :valkey,
  version: "0.1.0"
}
