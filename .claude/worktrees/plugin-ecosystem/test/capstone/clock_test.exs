defmodule Capstone.ClockTest do
  use ExUnit.Case, async: true

  alias Capstone.Clock
  alias Capstone.Manifest

  test "now/0 returns a string plugin.exs accepts as a timestamp" do
    now = Clock.now()

    # Asserted through the FORMAT'S OWN validator, not a regex written here: a
    # Z-spelled UTC instant that round-trips through DateTime is exactly what
    # Capstone.Manifest requires, and going through it is what keeps the clock
    # and the format from drifting apart.
    assert Manifest.validate_timestamp!(now, "generated_at") == :ok
    assert {:ok, _datetime, 0} = DateTime.from_iso8601(now)
    assert String.ends_with?(now, "Z")
  end

  test "now/0 advances" do
    # A constant would satisfy every assertion above. This is what says it is a
    # clock. ISO8601-Z strings of equal length compare lexicographically in
    # chronological order, so `>` is a real comparison here.
    first = Clock.now()
    Process.sleep(1)

    assert Clock.now() > first
  end
end
