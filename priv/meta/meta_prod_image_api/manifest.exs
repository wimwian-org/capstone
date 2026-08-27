%{
  deps: [],
  derived_against: %{phoenix: "1.8.9"},
  files: [
    {".dockerignore", :sole_owner},
    {"Dockerfile", :sole_owner},
    {"lib/APP/release.ex", :sole_owner},
    {"rel/overlays/bin/migrate", :sole_owner},
    {"rel/overlays/bin/migrate.bat", :sole_owner},
    {"rel/overlays/bin/server", :sole_owner},
    {"rel/overlays/bin/server.bat", :sole_owner}
  ],
  name: :prod_image_api,
  version: "0.1.0"
}
