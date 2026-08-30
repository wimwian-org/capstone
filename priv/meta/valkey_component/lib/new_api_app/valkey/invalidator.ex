defmodule NewApiApp.Valkey.Invalidator do
  @moduledoc """
  Cross-node L1 coherence, ported from `manage_infra`'s
  `ManageInfra.Cache.CoherentEvict` — see
  docs/superpowers/specs/2026-08-29-valkey-openbao-enhancements-design.md.

  `NewApiApp.Valkey.Cache` calls `broadcast/1` after every local `put/3`/
  `delete/1` — the LOCAL L1 write/delete already happened by the time this
  runs, so this module's only job is telling *peer* nodes to drop their own
  stale L1 copy. The broadcast is tagged with the originating node, and this
  module's own subscriber ignores a message tagged with its own node — a
  single-node deployment's self-broadcast is therefore a genuine no-op, not
  an accidental re-eviction of the value `Cache` just wrote.

  `default_ttl` (see `NewApiApp.Valkey.Cache`) is the correctness backstop if
  a broadcast is ever lost — this module is a coherence optimization, not the
  source of truth for staleness.
  """

  use GenServer

  @topic "valkey:invalidate"

  @doc "The PubSub topic peers subscribe to for eviction broadcasts."
  @spec topic() :: String.t()
  def topic, do: @topic

  @doc false
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Broadcasts that `key` changed, so every peer node drops its own L1 copy."
  @spec broadcast(term) :: :ok
  def broadcast(key) do
    Phoenix.PubSub.broadcast(NewApiApp.PubSub, @topic, {:evict, key, node()})
  end

  @impl true
  def init(_opts) do
    :ok = Phoenix.PubSub.subscribe(NewApiApp.PubSub, @topic)
    {:ok, %{}}
  end

  @impl true
  def handle_info({:evict, _key, origin}, state) when origin == node(), do: {:noreply, state}

  def handle_info({:evict, key, _origin}, state) do
    NewApiApp.Valkey.Cache.L1.delete(key)
    {:noreply, state}
  end
end
