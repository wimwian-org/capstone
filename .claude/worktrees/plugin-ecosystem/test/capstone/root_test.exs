defmodule Capstone.RootTest do
  # async: false — every test here mutates the node-global cwd.
  use ExUnit.Case, async: false

  alias Capstone.ProjectFixture
  alias Capstone.Root

  setup do
    dir = ProjectFixture.create!(tmp_dir(), :valid)
    original = File.cwd!()
    on_exit(fn -> File.cd!(original) end)
    {:ok, dir: dir}
  end

  defp tmp_dir do
    path = Path.join(System.tmp_dir!(), "capstone-target-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end

  test "new!/1 captures an absolute root that survives a later cd", %{dir: dir} do
    File.cd!(dir)
    # macOS `System.tmp_dir!/0` returns /var/..., a symlink to /private/var/...,
    # while `File.cwd!/0` reports the physical path. Capture it while still
    # inside the directory so the assertion names the directory we cd'd into.
    physical = File.cwd!()
    target = Root.new!(".")
    File.cd!("/")
    assert String.ends_with?(physical, Path.basename(dir))
    assert Root.path(target, "mix.exs") == Path.join(physical, "mix.exs")
  end

  test "new!/1 succeeds against a project whose mix.exs does not parse" do
    dir = ProjectFixture.create!(tmp_dir(), :broken_syntax)
    assert %Root{root: ^dir} = Root.new!(dir)
  end

  test "new!/1 raises InvalidRootError naming the absolute path" do
    missing = Path.join(System.tmp_dir!(), "nope-#{System.unique_integer([:positive])}")

    assert_raise Root.InvalidRootError, ~r/#{Regex.escape(missing)}/, fn ->
      Root.new!(missing)
    end
  end

  test "new!/1 raises when the directory has no mix.exs" do
    dir = ProjectFixture.create!(tmp_dir(), :no_mix_exs)
    assert_raise Root.InvalidRootError, ~r/mix\.exs/, fn -> Root.new!(dir) end
  end

  test "path/2 raises EscapeError for traversal and absolute paths", %{dir: dir} do
    target = Root.new!(dir)

    for escape <- ["../outside", "lib/../../x", "/etc/passwd"] do
      assert_raise Root.EscapeError, fn -> Root.path(target, escape) end
    end
  end

  test "path/2 returns the same bytes regardless of cwd", %{dir: dir} do
    target = Root.new!(dir)
    expected = Root.path(target, "mix.exs")

    for cwd <- [File.cwd!(), dir, "/"] do
      File.cd!(cwd)
      assert Root.path(target, "mix.exs") == expected
    end
  end

  test "%Root{} cannot be built without :root" do
    assert_raise ArgumentError, fn -> Code.eval_string("%Capstone.Root{}") end
  end
end
