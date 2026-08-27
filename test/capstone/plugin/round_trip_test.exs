defmodule Capstone.Plugin.RoundTripTest do
  # async: false — copies real trees under priv/meta.
  use ExUnit.Case, async: false

  alias Capstone.Baseline
  alias Capstone.Plugin.Apply

  @baseline "priv/meta/baseline_api"
  @plugin "priv/meta/meta_cache"
  @raw "priv/meta/cache_component"

  setup do
    target = Path.join(System.tmp_dir!(), "round-trip-#{System.unique_integer([:positive])}")
    File.cp_r!(@baseline, target)
    on_exit(fn -> File.rm_rf!(target) end)

    {:ok, target: target}
  end

  test "applying meta_cache to baseline_api reproduces cache_component", %{target: target} do
    {:ok, _component} = Apply.run(@plugin, target)

    expected = Baseline.tree(@raw)
    actual = Baseline.tree(target)

    # EVERY path, :manual included — anchoring places the positional hunk
    # exactly, so nothing is left for a human here. This is what proves derive
    # lossless: a dropped hunk, a misclassified mode or a lost byte of payload
    # all surface as a differing hash, and the failure NAMES the file.
    differing = for {path, hash} <- expected, actual[path] != hash, do: path

    assert differing == []
    assert Enum.sort(Map.keys(actual)) == Enum.sort(Map.keys(expected))
  end

  test "the :manual hunk is placed, not marked", %{target: target} do
    {:ok, _component} = Apply.run(@plugin, target)

    contents = File.read!(Path.join(target, "lib/new_api_app.ex"))

    assert contents == File.read!(Path.join(@raw, "lib/new_api_app.ex"))
    refute contents =~ Apply.marker_prefix("")
  end

  test "an anchor that cannot be located marks instead of guessing", %{target: target} do
    # Strip the anchor's distinguishing context. A wrong placement would be
    # silent; a marker is loud, and mix capstone.check gates it.
    File.write!(Path.join(target, "lib/new_api_app.ex"), "defmodule NewApiApp do\nend\n")

    {:ok, _component} = Apply.run(@plugin, target)

    assert File.read!(Path.join(target, "lib/new_api_app.ex")) =~ Apply.marker_prefix(:cache_app)
  end

  test "applying twice is a no-op", %{target: target} do
    {:ok, _} = Apply.run(@plugin, target)
    once = Baseline.tree(target)

    {:ok, _} = Apply.run(@plugin, target)

    # 7.3: "present and unchanged -> no-op".
    assert Baseline.tree(target) == once
  end

  test "the plugin installs into a differently named project" do
    other = Path.join(System.tmp_dir!(), "other-#{System.unique_integer([:positive])}")
    File.cp_r!(@baseline, other)
    on_exit(fn -> File.rm_rf!(other) end)

    # Rename as `mix new other_app` would have: the app atom, the module and the
    # file that carries it. Renaming only mix.exs would leave lib/other_app.ex
    # absent, which is a broken project rather than a differently named one.
    mix = Path.join(other, "mix.exs")
    File.write!(mix, String.replace(File.read!(mix), ":new_api_app", ":other_app"))

    root = Path.join(other, "lib/new_api_app.ex")

    File.write!(
      Path.join(other, "lib/other_app.ex"),
      String.replace(File.read!(root), "NewApiApp", "OtherApp")
    )

    File.rm!(root)

    {:ok, _} = Apply.run(@plugin, other)

    # The whole point of templating: paths AND content follow the target.
    assert File.read!(Path.join(other, "lib/other_app/cache.ex")) =~ "defmodule OtherApp.Cache"
    refute File.exists?(Path.join(other, "lib/new_api_app/cache.ex"))
  end
end
