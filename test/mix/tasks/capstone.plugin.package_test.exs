defmodule Mix.Tasks.Capstone.Plugin.PackageTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Capstone.Plugin.Package, as: Task

  @tag :tmp_dir
  test "packages priv/meta/meta_<name> into priv/plugins under the given cwd", %{tmp_dir: tmp} do
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

  test "raises when priv/meta/meta_<name> does not exist", %{} do
    assert_raise Mix.Error, ~r/does not exist/, fn -> Task.run(["nosuch"]) end
  end
end
