defmodule NewApiApp.Valkey.Cache.L1Test do
  # L1 is a supervised singleton started by the application (see
  # application.ex), not a per-test process — async: false, and setup clears
  # its state rather than starting a fresh instance.
  use ExUnit.Case, async: false

  alias NewApiApp.Valkey.Cache.L1

  setup do
    L1.delete_all!()
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
