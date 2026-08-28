defmodule NewApiApp.Cache.Store do
  @moduledoc """
  The real Nebulex cache `NewApiApp.Cache` reads and writes through.
  """

  use Nebulex.Cache, otp_app: :new_api_app, adapter: Nebulex.Adapters.Local
end
