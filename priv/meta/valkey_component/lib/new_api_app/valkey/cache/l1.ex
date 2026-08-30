defmodule NewApiApp.Valkey.Cache.L1 do
  @moduledoc "In-process ETS cache — the fast first-check level of `NewApiApp.Valkey.Cache`."

  use Nebulex.Cache,
    otp_app: :new_api_app,
    adapter: Nebulex.Adapters.Local
end
