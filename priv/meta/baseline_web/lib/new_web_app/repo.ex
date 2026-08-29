defmodule NewWebApp.Repo do
  use Ecto.Repo,
    otp_app: :new_web_app,
    adapter: Ecto.Adapters.Postgres
end
