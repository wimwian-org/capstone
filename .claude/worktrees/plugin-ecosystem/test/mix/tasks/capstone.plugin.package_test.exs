defmodule Mix.Tasks.Capstone.Plugin.PackageTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Capstone.Plugin.Package, as: Task

  # The plugin type is taken from priv/baselines.exs's own decoded keys rather
  # than interned from argv, so every test that reaches that far needs a
  # manifest under its cwd — the maintainer checkout this task only ever runs
  # in always has one.
  defp write_baselines!(tmp) do
    File.mkdir_p!(Path.join(tmp, "priv"))

    File.write!(
      Path.join(tmp, "priv/baselines.exs"),
      "%{cache: %{derived_from: :otp, path: \"priv/meta/cache_component\"}}\n"
    )
  end

  @tag :tmp_dir
  test "packages priv/meta/meta_<name> into priv/plugins under the given cwd", %{tmp_dir: tmp} do
    write_baselines!(tmp)
    File.mkdir_p!(Path.join(tmp, "priv/meta/meta_cache/files"))
    File.write!(Path.join(tmp, "priv/meta/meta_cache/manifest.exs"), "%{name: :cache}\n")

    File.cd!(tmp, fn ->
      Task.run(["cache"])
    end)

    archives = Path.wildcard(Path.join(tmp, "priv/plugins/cache-*.tar.gz"))
    assert length(archives) == 1
  end

  test "raises without exactly one plugin name" do
    assert_raise Mix.Error, ~r/expects one plugin name/, fn -> Task.run([]) end
    assert_raise Mix.Error, ~r/expects one plugin name/, fn -> Task.run(["a", "b"]) end
  end

  @tag :tmp_dir
  test "raises when priv/meta/meta_<name> does not exist", %{tmp_dir: tmp} do
    write_baselines!(tmp)

    File.cd!(tmp, fn ->
      assert_raise Mix.Error, ~r/meta_cache does not exist/, fn -> Task.run(["cache"]) end
    end)
  end

  @tag :tmp_dir
  test "raises naming priv/baselines.exs when the plugin type is not one of its keys",
       %{tmp_dir: tmp} do
    write_baselines!(tmp)

    File.cd!(tmp, fn ->
      assert_raise Mix.Error, ~r/unknown plugin type nosuch.*priv\/baselines\.exs/, fn ->
        Task.run(["nosuch"])
      end
    end)
  end
end
