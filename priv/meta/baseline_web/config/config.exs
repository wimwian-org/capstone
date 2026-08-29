# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :new_web_app,
  ecto_repos: [NewWebApp.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :new_web_app, NewWebAppWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: NewWebAppWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: NewWebApp.PubSub,
  live_view: [signing_salt: "<<SIGNING_SALT>>"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :new_web_app, NewWebApp.Mailer, adapter: Swoosh.Adapters.Local

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Vite (assets/vite.config.mjs) owns the Tailwind build now.
config :live_svelte, ssr: false

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
