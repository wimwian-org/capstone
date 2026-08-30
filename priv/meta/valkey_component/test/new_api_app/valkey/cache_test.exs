defmodule NewApiApp.Valkey.CacheTest do
  use ExUnit.Case, async: false

  alias NewApiApp.Valkey.Breaker
  alias NewApiApp.Valkey.Cache
  alias NewApiApp.Valkey.Cache.L1

  # A deterministic fake L2 backend, swapped in via config — same pattern as
  # BreakerTest's FakeBackend. :persistent_term, not Process.put/get, because
  # Breaker.run/2 executes the backend call inside a Task.async'd process,
  # which does not inherit the test process's process dictionary.
  defmodule FakeL2Backend do
    def get!(key, _default \\ nil, _opts \\ []),
      do: :persistent_term.get({:fake_l2_get, key}, nil)
  end

  # A backend that cannot succeed, and counts the calls that reach it so a
  # test can tell "the circuit was open" from "the call failed again".
  # `backend: nil` would NOT do — Breaker's own `config()[:backend] ||
  # Cache.L2` falls through to the real L2 on a nil, so a test written that
  # way passes or fails on whether a sidecar happens to be running.
  defmodule UnreachableBackend do
    @calls {__MODULE__, :calls}

    def call_count, do: :persistent_term.get(@calls, 0)
    def reset_calls, do: :persistent_term.put(@calls, 0)
    def erase_calls, do: :persistent_term.erase(@calls)

    def get!(_key, _default \\ nil, _opts \\ []), do: fail!()
    def put_new!(_key, _value, _opts \\ []), do: fail!()

    defp fail! do
      :persistent_term.put(@calls, call_count() + 1)
      raise "l2 unreachable"
    end
  end

  # L1 and Invalidator are supervised singletons started by the application
  # (see application.ex), not per-test processes — clear L1's state instead
  # of starting fresh instances.
  setup do
    L1.delete_all!()
    Breaker.reset!()
    on_exit(&Breaker.reset!/0)
    :ok
  end

  test "get/1 on an L1 hit never touches the breaker" do
    L1.put("k", "cached")
    assert Cache.get("k") == "cached"
  end

  test "get/1 on an L1 miss and a Breaker/L2 hit backfills L1" do
    Application.put_env(:new_api_app, Breaker,
      backend: FakeL2Backend,
      timeout_ms: 50,
      failure_threshold: 3,
      cooldown_ms: 30
    )

    on_exit(fn -> Application.delete_env(:new_api_app, Breaker) end)

    :persistent_term.put({:fake_l2_get, "k2"}, "from-l2")
    on_exit(fn -> :persistent_term.erase({:fake_l2_get, "k2"}) end)

    assert L1.get!("k2") == nil

    assert Cache.get("k2") == "from-l2"
    assert L1.get!("k2") == "from-l2"
  end

  test "get/1 degrades to nil when L1 misses and the breaker's circuit is open" do
    use_unreachable_backend()

    # failure_threshold: 1, so this first miss both fails and opens the
    # circuit — rather than poking Breaker's :atomics state directly.
    assert Cache.get("missing") == nil

    UnreachableBackend.reset_calls()
    assert Cache.get("missing") == nil

    assert UnreachableBackend.call_count() == 0,
           "the circuit was not open: the backend was called a second time"
  end

  test "put_new/2 propagates (raises) rather than silently degrading" do
    use_unreachable_backend()

    # The failing call itself raises rather than fabricating a boolean...
    assert_raise RuntimeError, ~r/l2 unreachable/, fn -> Cache.put_new("k", "v") end

    # ...and having opened the circuit, the next one is refused outright —
    # still a raise, still never a made-up answer.
    assert_raise RuntimeError, ~r/circuit open/, fn -> Cache.put_new("k", "v") end
  end

  defp use_unreachable_backend do
    Application.put_env(:new_api_app, Breaker,
      backend: UnreachableBackend,
      timeout_ms: 50,
      failure_threshold: 1,
      cooldown_ms: 1_000
    )

    UnreachableBackend.reset_calls()

    on_exit(fn ->
      Application.delete_env(:new_api_app, Breaker)
      UnreachableBackend.erase_calls()
    end)
  end
end
