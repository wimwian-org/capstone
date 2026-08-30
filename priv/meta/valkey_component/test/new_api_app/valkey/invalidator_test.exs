defmodule NewApiApp.Valkey.InvalidatorTest do
  use ExUnit.Case, async: false

  alias NewApiApp.Valkey.Cache.L1
  alias NewApiApp.Valkey.Invalidator

  # L1 and Invalidator are supervised singletons started by the application
  # (see application.ex), not per-test processes — clear L1's state instead
  # of starting fresh instances.
  setup do
    L1.delete_all!()
    :ok
  end

  test "broadcast/1 from this same node does not evict this node's own L1 entry" do
    L1.put("k", "v")
    Invalidator.broadcast("k")
    # The broadcast is async (PubSub); give the subscriber a beat to receive
    # it and prove it deliberately did nothing, rather than racing the assert.
    :sys.get_state(Process.whereis(Invalidator))

    assert L1.get!("k") == "v"
  end

  test "an eviction broadcast tagged with a different origin node evicts this node's L1 entry" do
    L1.put("k", "v")

    Phoenix.PubSub.broadcast(NewApiApp.PubSub, Invalidator.topic(), {:evict, "k", :peer@nohost})
    :sys.get_state(Process.whereis(Invalidator))

    assert L1.get!("k") == nil
  end
end
