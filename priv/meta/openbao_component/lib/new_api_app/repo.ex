defmodule NewApiApp.Repo do
  use Ecto.Repo,
    otp_app: :new_api_app,
    adapter: Ecto.Adapters.Postgres
end
