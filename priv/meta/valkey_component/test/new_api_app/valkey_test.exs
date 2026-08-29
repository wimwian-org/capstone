defmodule NewApiApp.ValkeyTest do
  use ExUnit.Case, async: true

  # Redix has no official test/stub tooling the way Req.Test does, so this
  # exercises the real sidecar rather than a mock -- excluded by default
  # (see test/test_helper.exs), opt in with `mix test --include valkey`.
  @moduletag :valkey

  test "set/2 then get/1 round-trips a value" do
    key = "valkey_test/#{System.unique_integer([:positive])}"

    assert {:ok, "OK"} = NewApiApp.Valkey.set(key, "hello")
    assert {:ok, "hello"} = NewApiApp.Valkey.get(key)
  end

  test "set/3 with ex: sets a TTL on the key" do
    key = "valkey_test/#{System.unique_integer([:positive])}"

    assert {:ok, "OK"} = NewApiApp.Valkey.set(key, "hello", ex: 30)
    assert {:ok, ttl} = Redix.command(NewApiApp.Valkey, ["TTL", key])
    assert ttl in 1..30
  end
end
