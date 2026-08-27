defmodule Capstone.BoundaryGuardTest do
  use ExUnit.Case, async: true

  alias Capstone.BoundaryGuard
  alias Capstone.Factory

  test "no module under lib/ mentions any banned token" do
    assert BoundaryGuard.scan("lib", BoundaryGuard.banned()) == %{}
  end

  test "the guard visited every .ex under lib/ except the exempt ones" do
    # "at least one file" is satisfied by a broken glob returning one file --
    # the same degrade-to-nearly-empty failure the rest of this design exists to
    # prevent. The comparison must go through scan/2 itself: re-globbing here and
    # comparing the glob to itself is a tautology that cannot fail.
    #
    # "" is a substring of every file, so every file scan/2 visits shows up as a
    # key; a degraded glob yields a strictly smaller -- and diffable -- set.
    expected =
      ("lib/**/*.ex"
       |> Path.wildcard()
       |> Enum.reject(&String.starts_with?(&1, BoundaryGuard.vendor()))) --
        BoundaryGuard.exempt()

    assert expected != []

    scanned = "lib" |> BoundaryGuard.scan([""]) |> Map.keys() |> Enum.sort()
    assert scanned == Enum.sort(expected)
  end

  test "the vendored tree is skipped, and would otherwise fail the scan" do
    # Same reasoning as the clock below: an exclusion that stopped being needed
    # should say so. Vendored source is third-party and pristine by design, so
    # these hits are expected and are not ours to fix -- but if they ever
    # vanished, the prefix would be dead weight nobody would notice.
    vendored = Path.wildcard(BoundaryGuard.vendor() <> "**/*.ex")
    assert vendored != [], "the vendored tree globbed to nothing"

    offenders =
      Enum.filter(vendored, &(BoundaryGuard.violations(File.read!(&1), ["__DIR__"]) != []))

    assert offenders != [], "no vendored file trips the ban any more -- drop the prefix"
    refute Map.has_key?(BoundaryGuard.scan("lib", BoundaryGuard.banned()), hd(offenders))
  end

  test "exactly two files are exempt: the clock and the config project atom" do
    # Equality, not membership: a third exemption must FAIL a test rather than
    # pass unnoticed. The ban is the design; each hole in it is a decision.
    assert BoundaryGuard.exempt() == [
             "lib/capstone/clock.ex",
             "lib/capstone/config/project.ex"
           ]
  end

  test "the clock would otherwise fail the scan" do
    # Without this, the exemption could outlive its reason in silence: someone
    # rewrites Capstone.Clock to take an injected instant, the ban stops applying to
    # it, and the hole stays open with nothing pointing at it.
    source = File.read!("lib/capstone/clock.ex")

    assert BoundaryGuard.violations(source, BoundaryGuard.banned()) == ["DateTime.utc_now"]
  end

  test "the config project module would otherwise fail the scan" do
    # Same reasoning as the clock above: if Capstone.Config.Project ever stops
    # deriving :app with String.to_atom/1, this exemption should start failing
    # loudly rather than sitting there unnoticed.
    source = File.read!("lib/capstone/config/project.ex")

    assert BoundaryGuard.violations(source, BoundaryGuard.banned()) == ["String.to_atom"]
  end

  test "violations/2 fires for every banned token" do
    for token <- BoundaryGuard.banned() do
      %{source: source} = Factory.build(:banned_token_source, token: token)
      assert token in BoundaryGuard.violations(source, BoundaryGuard.banned())
    end
  end
end
