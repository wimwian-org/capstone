%{
  deps: ["{:nebulex, \"~> 2.6\"}"],
  files: [
    {"lib/APP/cache.ex", :sole_owner},
    {"README.md", :contributes, [key: :cache_readme]},
    {"lib/APP.ex", :manual, [after: ["      :world", "", "  \"\"\""], key: :cache_app]}
  ],
  name: :cache,
  version: "0.1.0"
}
