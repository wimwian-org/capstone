defmodule Capstone.Plugin.CqrsRoundTripTest do
  # async: false — copies real trees under priv/meta.
  use ExUnit.Case, async: false

  alias Capstone.Baseline
  alias Capstone.Plugin.Apply

  @baseline "priv/meta/baseline_api"
  @plugin "priv/meta/meta_cqrs"
  @raw "priv/meta/cqrs_component"

  setup do
    target = Path.join(System.tmp_dir!(), "cqrs-round-trip-#{System.unique_integer([:positive])}")
    File.cp_r!(@baseline, target)
    on_exit(fn -> File.rm_rf!(target) end)

    {:ok, target: target}
  end

  test "applying meta_cqrs to baseline_api reproduces cqrs_component", %{target: target} do
    {:ok, _component} = Apply.run(@plugin, target)

    expected = Baseline.tree(@raw)
    actual = Baseline.tree(target)

    # lib/new_api_app/application.ex excluded: its hunk both ADDS and REMOVES
    # lines, so `place_manual/5` routes it through `Apply.mark_removal/6`
    # rather than `Apply.place/6` — and `mark_removal/6`'s own docs say a
    # removal hunk is "always" marked as a conflict region, never anchored.
    # Applying to a fresh target can therefore never byte-for-byte reproduce
    # cqrs_component's already-resolved application.ex; the marker below is
    # the actual, by-design outcome.
    differing =
      for {path, hash} <- expected,
          path != "lib/new_api_app/application.ex",
          actual[path] != hash,
          do: path

    assert differing == []
    assert Enum.sort(Map.keys(actual)) == Enum.sort(Map.keys(expected))

    assert File.read!(Path.join(target, "lib/new_api_app/application.ex")) =~
             Apply.marker_prefix(:cqrs_application)
  end

  test "application.ex's removal hunk always marks a conflict on a fresh target — it never reaches the anchor-based placement path that :cache's :manual entries use",
       %{target: target} do
    {:ok, _component} = Apply.run(@plugin, target)

    assert File.read!(Path.join(target, "lib/new_api_app/application.ex")) =~
             Apply.marker_prefix(:cqrs_application)
  end

  test "applying twice is a no-op", %{target: target} do
    {:ok, _} = Apply.run(@plugin, target)
    once = Baseline.tree(target)

    {:ok, _} = Apply.run(@plugin, target)

    assert Baseline.tree(target) == once
  end

  test "the plugin installs into a differently named project" do
    other = Path.join(System.tmp_dir!(), "cqrs-other-#{System.unique_integer([:positive])}")
    File.cp_r!(@baseline, other)
    on_exit(fn -> File.rm_rf!(other) end)

    mix = Path.join(other, "mix.exs")
    File.write!(mix, String.replace(File.read!(mix), ":new_api_app", ":other_app"))

    root = Path.join(other, "lib/new_api_app.ex")

    File.write!(
      Path.join(other, "lib/other_app.ex"),
      String.replace(File.read!(root), "NewApiApp", "OtherApp")
    )

    File.rm!(root)

    # A real `mix new other_app` also renames the app's own lib/<app>/
    # subdirectory and rewrites the module name inside each file — this
    # plugin's application.ex edit needs lib/APP/application.ex to exist
    # at the renamed path.
    File.rename!(Path.join(other, "lib/new_api_app"), Path.join(other, "lib/other_app"))

    for file <- Path.wildcard(Path.join(other, "lib/other_app/**/*.ex")) do
      File.write!(file, String.replace(File.read!(file), "NewApiApp", "OtherApp"))
    end

    {:ok, _} = Apply.run(@plugin, other)

    assert File.read!(Path.join(other, "lib/other_app/cqrs/dispatcher.ex")) =~
             "defmodule OtherApp.CQRS.Dispatcher"

    refute File.exists?(Path.join(other, "lib/new_api_app/cqrs/dispatcher.ex"))
  end
end
