%{
  deps: [
    "{:nebulex, \"~> 3.0\"}",
    "{:nebulex_local, \"~> 3.0\"}",
    "{:nebulex_redis_adapter, \"~> 3.0\"}",
    "{:redix, \"~> 1.8\"}"
  ],
  files: [
    {"lib/APP/valkey/breaker.ex", :sole_owner},
    {"lib/APP/valkey/cache.ex", :sole_owner},
    {"lib/APP/valkey/cache/l1.ex", :sole_owner},
    {"lib/APP/valkey/cache/l2.ex", :sole_owner},
    {"lib/APP/valkey/invalidator.ex", :sole_owner},
    {"test/APP/valkey/breaker_test.exs", :sole_owner},
    {"test/APP/valkey/cache/l1_test.exs", :sole_owner},
    {"test/APP/valkey/cache_test.exs", :sole_owner},
    {"test/APP/valkey/invalidator_test.exs", :sole_owner},
    {"README.md", :contributes, [key: :valkey_readme]},
    {"compose.yaml", :contributes, [key: :valkey_compose]},
    {"config/dev.exs", :contributes, [key: :valkey_dev]},
    {"config/runtime.exs", :contributes, [key: :valkey_runtime, at: {:env, :prod}]},
    {"config/test.exs", :contributes, [key: :valkey_test]},
    {"lib/APP/application.ex", :contributes,
     [
       key: :valkey_application,
       child: [
         "<%= @module %>.Valkey.Cache.L1",
         "<%= @module %>.Valkey.Breaker",
         "<%= @module %>.Valkey.Invalidator"
       ]
     ]}
  ],
  name: :valkey,
  version: "0.1.0"
}
