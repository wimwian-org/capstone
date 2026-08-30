import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :new_api_app, NewApiApp.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "new_api_app_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :new_api_app, NewApiAppWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "<<SECRET_KEY_BASE>>",
  server: false

# In test we don't send emails
config :new_api_app, NewApiApp.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Configure the OpenBao (Vault-compatible) secrets sidecar. Same fixed
# dev-mode token compose.yaml's openbao service is seeded with, so
# `mix test --include openbao` can authenticate without extra setup.
config :new_api_app, NewApiApp.Vault,
  base_url: System.get_env("OPENBAO_ADDR", "http://localhost:8200"),
  method: :token,
  token: System.get_env("OPENBAO_TOKEN", "new_api_app-dev-root-token"),
  role_id: nil,
  secret_id: nil,
  mount: "approle",
  timeout_ms: 5_000
