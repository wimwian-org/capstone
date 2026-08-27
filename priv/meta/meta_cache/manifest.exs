%{
  deps: ["{:nebulex, \"~> 3.0\"}"],
  files: [
    {"lib/APP/cache.ex", :sole_owner},
    {"README.md", :contributes, [key: :cache_readme]},
    {"lib/APP.ex", :manual,
     [
       after: [
         "  Contexts are also responsible for managing your data, regardless",
         "  if it comes from the database, an external API or others.",
         "  \"\"\""
       ],
       key: :cache_app
     ]}
  ],
  name: :cache,
  version: "0.1.0"
}
