defmodule Capstone.VersionGuardTest do
  use ExUnit.Case, async: true

  alias Capstone.VersionGuard

  @locked %{capstone: {:hex, :capstone, "0.7.0", "h", [:mix], [], "hexpm", "c"}}

  test "raises when the loaded version is older than the locked one" do
    spec_fun = fn :capstone, :vsn -> ~c"0.5.0" end
    lock_fun = fn -> @locked end

    assert_raise Mix.Error, ~r/capstone 0\.5\.0 is loaded.*pins capstone 0\.7\.0/s, fn ->
      VersionGuard.verify!(spec_fun, lock_fun)
    end
  end

  test "does not raise when the loaded version equals the locked one" do
    spec_fun = fn :capstone, :vsn -> ~c"0.7.0" end
    assert VersionGuard.verify!(spec_fun, fn -> @locked end) == :ok
  end

  test "does not raise when the loaded version is newer than the locked one" do
    spec_fun = fn :capstone, :vsn -> ~c"0.9.0" end
    assert VersionGuard.verify!(spec_fun, fn -> @locked end) == :ok
  end

  test "is a no-op when nothing is loaded" do
    spec_fun = fn :capstone, :vsn -> nil end
    assert VersionGuard.verify!(spec_fun, fn -> @locked end) == :ok
  end

  test "is a no-op when nothing is locked (a path dependency, or none at all)" do
    spec_fun = fn :capstone, :vsn -> ~c"0.7.0" end
    assert VersionGuard.verify!(spec_fun, fn -> %{} end) == :ok
  end

  test "verify!/0 (real lookups) does not raise in this checkout" do
    # This checkout IS :capstone, not a dependent of it, so
    # Mix.Dep.Lock.read/0 has no entry for it and this is a no-op by
    # construction — this test pins that today's real checkout doesn't crash.
    assert VersionGuard.verify!() == :ok
  end
end
