defmodule Capstone.Plugin.DeletionTest do
  # async: false — derives into a throwaway directory and runs a mix task.
  use ExUnit.Case, async: false

  alias Capstone.Factory
  alias Capstone.Plugin.Apply
  alias Capstone.Plugin.Derive
  alias Mix.Tasks.Capstone.Check

  @names %{app: "myapp", module: "Myapp", name: "myapp"}
  @baseline_css ~s|@import "tailwindcss" source(none);\n@source "../css";\n@plugin "daisyui";\n|

  setup do
    %{baseline: baseline, meta: meta} = Factory.build(:meta_pair, variety: :rewrite)
    out = Path.join(System.tmp_dir!(), "deletion-out-#{System.unique_integer([:positive])}")
    target = Path.join(System.tmp_dir!(), "deletion-tgt-#{System.unique_integer([:positive])}")

    File.cp_r!(baseline, target)
    on_exit(fn -> File.rm_rf!(out) end)
    on_exit(fn -> File.rm_rf!(target) end)

    {:ok, _component} =
      Derive.run(name: :svelte, baseline: baseline, meta: meta, names: @names, out: out)

    {:ok, out: out, target: target}
  end

  test "the rewritten stylesheet is a conflict, not a concatenation", %{out: out, target: target} do
    {:ok, _component} = Apply.run(out, target)

    contents = File.read!(Path.join(target, "assets/css/app.css"))

    # Measured before the fix: daisyUI survived, @import "tailwindcss" appeared
    # twice, and Apply.run/2 returned :ok. Now both halves sit inside one keyed
    # region and nothing outside it moved.
    assert contents =~ Apply.marker_prefix(:svelte_app)
    assert contents =~ ~s|@source "../svelte/**/*.svelte";|

    # Everything ahead of the region is the target's untouched original: the
    # added line exists ONLY inside the markers, never applied silently.
    [before_region, _region] = String.split(contents, Apply.marker_prefix(:svelte_app), parts: 2)

    assert before_region == @baseline_css
    refute before_region =~ ~s|@source "../svelte/**/*.svelte";|
  end

  test "mix capstone.check fails while the region remains", %{out: out, target: target} do
    {:ok, _component} = Apply.run(out, target)

    assert_raise Mix.Error, ~r/unresolved manual regions/, fn ->
      Check.run([target])
    end
  end

  test "applying twice leaves the region exactly once", %{out: out, target: target} do
    {:ok, _component} = Apply.run(out, target)
    once = File.read!(Path.join(target, "assets/css/app.css"))

    {:ok, _component} = Apply.run(out, target)

    assert File.read!(Path.join(target, "assets/css/app.css")) == once
  end
end
