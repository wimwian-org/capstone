# Internal Nebulex cache - module private, not part of public API
defmodule NewApiApp.Valkey.Cache.L2.NebuAdapter do
  @moduledoc false
  use Nebulex.Cache,
    otp_app: :new_api_app,
    adapter: Nebulex.Adapters.Redis
end

# Public wrapper that provides the expected interface
defmodule NewApiApp.Valkey.Cache.L2 do
  @moduledoc "Talks to the Valkey sidecar. Reached only through `NewApiApp.Valkey.Breaker`."

  # Re-export the Nebulex cache functions for supervision
  defdelegate start_link(opts), to: NewApiApp.Valkey.Cache.L2.NebuAdapter
  defdelegate child_spec(opts), to: NewApiApp.Valkey.Cache.L2.NebuAdapter

  @doc "Gets the value at `key`, or `nil` if it isn't set."
  def get(key) do
    case NewApiApp.Valkey.Cache.L2.NebuAdapter.get(key) do
      {:ok, value} -> value
      nil -> nil
      value -> value
    end
  end

  @doc "Sets `key` to `value`."
  def put(key, value) do
    case NewApiApp.Valkey.Cache.L2.NebuAdapter.put(key, value) do
      :ok -> :ok
      other -> other
    end
  end
end
