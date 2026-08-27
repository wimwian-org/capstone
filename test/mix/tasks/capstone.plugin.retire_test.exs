defmodule Mix.Tasks.Capstone.Plugin.RetireTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Capstone.Plugin.Retire, as: Task

  @tag :tmp_dir
  test "retires an archive under the given cwd's priv/plugins", %{tmp_dir: tmp} do
    dir = Path.join(tmp, "priv/plugins")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "cache-1.20.3-0.1.0-aaaaaaaaaaaa.tar.gz"), "")

    File.cd!(tmp, fn -> Task.run(["cache-1.20.3-0.1.0-aaaaaaaaaaaa.tar.gz"]) end)

    assert File.read!(Path.join(dir, "retired.exs")) =~ "cache-1.20.3-0.1.0-aaaaaaaaaaaa.tar.gz"
  end

  test "raises without exactly one archive filename" do
    assert_raise Mix.Error, ~r/expects one archive filename/, fn -> Task.run([]) end
  end

  @tag :tmp_dir
  test "raises when the archive does not exist", %{tmp_dir: tmp} do
    File.mkdir_p!(Path.join(tmp, "priv/plugins"))

    File.cd!(tmp, fn ->
      assert_raise Mix.Error, ~r/does not exist/, fn -> Task.run(["nosuch.tar.gz"]) end
    end)
  end
end
