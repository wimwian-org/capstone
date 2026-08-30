defmodule Mix.Tasks.Capstone.Plugin.DeriveTest do
  # async: false — the task writes priv/meta/meta_cache/ inside the repo tree.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Capstone.Plugin.Derive

  @out "priv/meta/meta_cache"

  test "the task module exposes a @shortdoc" do
    assert Mix.Task.shortdoc(Derive) =~ "raw working project"
  end

  test "re-deriving reproduces the checked-in plugin byte for byte" do
    # SDD 10: "CI can assert that derive still reproduces the checked-in
    # plugin." This is that assertion, and it is what makes the diff — not
    # the manifest — the source of truth.
    before =
      @out
      |> Path.join("**")
      |> Path.wildcard()
      |> Enum.reject(&File.dir?/1)
      |> Map.new(&{&1, File.read!(&1)})

    refute before == %{}

    capture_io(fn -> Derive.run(["cache"]) end)

    after_run =
      @out
      |> Path.join("**")
      |> Path.wildcard()
      |> Enum.reject(&File.dir?/1)
      |> Map.new(&{&1, File.read!(&1)})

    assert after_run == before
  end

  test "reports what it wrote" do
    output = capture_io(fn -> Derive.run(["cache"]) end)

    assert output =~ "wrote #{@out}/manifest.exs"
    assert output =~ ~r/files: 6, deps: 2/
  end

  test "an unknown plugin names the manifest" do
    assert_raise Mix.Error, ~r/nosuch has no entry in priv\/baselines\.exs/, fn ->
      Derive.run(["nosuch"])
    end
  end

  test "a baseline entry has no derived_from and is refused" do
    # :api is a baseline, not a raw working project — it has nothing to diff against.
    assert_raise Mix.Error, ~r/api has no derived_from/, fn ->
      Derive.run(["api"])
    end
  end

  test "a raw project that deletes a baseline file is refused, naming the path" do
    # SDD 7.3 has no ownership mode for a removal, so derive must refuse rather
    # than emit a plugin that silently cannot express part of its own diff.
    file = "priv/meta/cache_component/README.md"
    original = File.read!(file)
    on_exit(fn -> File.write!(file, original) end)
    File.rm!(file)

    assert_raise Mix.Error, ~r/deletes baseline files.*README\.md/s, fn ->
      Derive.run(["cache"])
    end
  end

  test "a raw project that adds a binary file is refused, naming the path" do
    # Template.capture/2 correctly refuses to template binary content; derive
    # must turn that refusal into a named, actionable error rather than the
    # bare MatchError this reproduces without the fix (deep in entries/2).
    file = "priv/meta/cache_component/lib/new_api_app/dump.bin"
    on_exit(fn -> File.rm(file) end)
    File.write!(file, <<0, 159, 146, 150>>)

    assert_raise Mix.Error, ~r/adds or modifies binary file.*dump\.bin/s, fn ->
      Derive.run(["cache"])
    end
  end

  test "a raw project that turns a baseline file binary is refused, naming the path" do
    # The predecessor fix only guarded changes.added; a raw component that
    # MODIFIES an existing baseline file into binary content (e.g. rebranding
    # a favicon) hit the same unguarded MatchError in shared/2 instead.
    file = "priv/meta/cache_component/README.md"
    original = File.read!(file)
    on_exit(fn -> File.write!(file, original) end)
    File.write!(file, <<0, 159, 146, 150>>)

    assert_raise Mix.Error, ~r/adds or modifies binary file.*README\.md/s, fn ->
      Derive.run(["cache"])
    end
  end

  test "run/1 requires exactly one plugin name" do
    assert_raise Mix.Error, ~r/expects one plugin name/, fn ->
      Derive.run([])
    end
  end
end
