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

# Configure the Valkey (Redis-protocol) KV sidecar. Same host/port
# compose.yaml's valkey service publishes, so `mix test --include valkey`
# can connect without extra setup.
config :new_api_app, NewApiApp.Valkey.Cache.L1,
  gc_interval: :timer.hours(1),
  max_size: 1_000_000,
  allocated_memory: 100_000_000

config :new_api_app, NewApiApp.Valkey.Cache.L2,
  conn_opts: [
    host: System.get_env("VALKEY_HOST", "localhost"),
    port: String.to_integer(System.get_env("VALKEY_PORT", "6379"))
  ],
  pool_size: 5

config :new_api_app, NewApiApp.Valkey.Breaker,
  timeout_ms: 100,
  failure_threshold: 3,
  cooldown_ms: :timer.seconds(30)

config :new_api_app, NewApiApp.Valkey.Cache, default_ttl: :timer.minutes(10)

# Legacy config for NewApiApp.Valkey (kept until Task 6 removes it from supervision)
config :new_api_app, NewApiApp.Valkey,
  host: System.get_env("VALKEY_HOST", "localhost"),
  port: String.to_integer(System.get_env("VALKEY_PORT", "6379"))
