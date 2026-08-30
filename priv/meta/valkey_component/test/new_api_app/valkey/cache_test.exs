defmodule NewApiApp.Valkey.CacheTest do
  use ExUnit.Case, async: false

  alias NewApiApp.Valkey.Breaker
  alias NewApiApp.Valkey.Cache
  alias NewApiApp.Valkey.Cache.L1

  setup do
    start_supervised!(L1)
    start_supervised!(NewApiApp.Valkey.Invalidator)
    Breaker.reset!()
    on_exit(&Breaker.reset!/0)
    :ok
  end

  test "get/1 on an L1 hit never touches the breaker" do
    L1.put("k", "cached")
    assert Cache.get("k") == "cached"
  end

  test "get/1 degrades to nil when L1 misses and the breaker's circuit is open" do
    Application.put_env(:new_api_app, Breaker,
      backend: nil,
      timeout_ms: 5,
      failure_threshold: 1,
      cooldown_ms: 1_000
    )

    :atomics.put(:persistent_term.get({Breaker, :state}, :atomics.new(3, signed: true)), 1, 1)

    assert Cache.get("missing") == nil
  end

  test "put_new/2 propagates (raises) rather than silently degrading" do
    Application.put_env(:new_api_app, Breaker,
      backend: nil,
      timeout_ms: 5,
      failure_threshold: 1,
      cooldown_ms: 1_000
    )

    ref = :atomics.new(3, signed: true)
    :atomics.put(ref, 1, 1)
    :persistent_term.put({Breaker, :state}, ref)

    assert_raise RuntimeError, ~r/circuit open/, fn -> Cache.put_new("k", "v") end
  end
end
