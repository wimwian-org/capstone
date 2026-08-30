defmodule NewApiApp.Valkey.Cache.L1Test do
  use ExUnit.Case, async: true

  alias NewApiApp.Valkey.Cache.L1

  setup do
    start_supervised!(L1)
    :ok
  end

  test "put/3 then get/2 round-trips a value with no live sidecar needed" do
    assert :ok = L1.put("k", "v")
    assert L1.get!("k") == "v"
  end

  test "get/2 on a missing key returns nil" do
    assert L1.get!("missing") == nil
  end
end
