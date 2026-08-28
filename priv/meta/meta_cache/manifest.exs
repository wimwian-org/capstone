%{
  deps: ["{:nebulex, \"~> 3.0\"}", "{:nebulex_local, \"~> 3.0\"}"],
  files: [
    {"lib/APP/cache.ex", :sole_owner},
    {"lib/APP/cache/store.ex", :sole_owner},
    {"README.md", :contributes, [key: :cache_readme]},
    {"config/config.exs", :contributes, [key: :cache_config, at: :before_import]},
    {"lib/APP.ex", :manual,
     [
       after: [
         "  Contexts are also responsible for managing your data, regardless",
         "  if it comes from the database, an external API or others.",
         "  \"\"\""
       ],
       key: :cache_app
     ]},
    {"lib/APP/application.ex", :contributes,
     [key: :cache_application, child: "<%= @module %>.Cache.Store"]}
  ],
  name: :cache,
  version: "0.1.0"
}
