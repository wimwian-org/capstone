defmodule NewApiApp.Valkey.Cache.L2 do
  @moduledoc "Talks to the Valkey sidecar. Reached only through `NewApiApp.Valkey.Breaker`."

  use Nebulex.Cache,
    otp_app: :new_api_app,
    adapter: Nebulex.Adapters.Redis
end
