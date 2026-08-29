defmodule NewApiApp.Valkey do
  @moduledoc "A thin Redix client for the Valkey (Redis-protocol) KV sidecar."

  @doc false
  def child_spec(_opts) do
    config = Application.fetch_env!(:new_api_app, __MODULE__)

    Redix.child_spec(
      name: __MODULE__,
      host: Keyword.fetch!(config, :host),
      port: Keyword.fetch!(config, :port)
    )
  end

  @doc "Gets the value at `key`, or `nil` if it isn't set."
  def get(key), do: Redix.command(__MODULE__, ["GET", key])

  @doc "Sets `key` to `value`. Pass `ex: seconds` to expire it after `seconds`."
  def set(key, value, opts \\ [])

  def set(key, value, ex: seconds),
    do: Redix.command(__MODULE__, ["SET", key, value, "EX", to_string(seconds)])

  def set(key, value, []), do: Redix.command(__MODULE__, ["SET", key, value])
end
