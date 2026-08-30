# Internal Nebulex cache - module private, not part of public API
defmodule NewApiApp.Valkey.Cache.L1.NebuAdapter do
  @moduledoc false
  use Nebulex.Cache,
    otp_app: :new_api_app,
    adapter: Nebulex.Adapters.Local
end

# Public wrapper that provides the expected interface
defmodule NewApiApp.Valkey.Cache.L1 do
  @moduledoc "In-process ETS cache — the fast first-check level of `NewApiApp.Valkey.Cache`."

  # Re-export the Nebulex cache functions for supervision
  defdelegate start_link(opts), to: NewApiApp.Valkey.Cache.L1.NebuAdapter
  defdelegate child_spec(opts), to: NewApiApp.Valkey.Cache.L1.NebuAdapter

  @doc "Gets the value at `key`, or `nil` if it isn't set."
  def get(key) do
    case NewApiApp.Valkey.Cache.L1.NebuAdapter.get(key) do
      {:ok, value} -> value
      nil -> nil
      value -> value
    end
  end

  @doc "Sets `key` to `value`."
  def put(key, value) do
    case NewApiApp.Valkey.Cache.L1.NebuAdapter.put(key, value) do
      :ok -> :ok
      other -> other
    end
  end
end
