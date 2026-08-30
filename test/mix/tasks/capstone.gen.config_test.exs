defmodule Mix.Tasks.Capstone.Gen.ConfigTest do
  # async: false — "defaults to target.exs in the current directory" below
  # mutates the node-global cwd via File.cd!/2, which races every other async
  # test that resolves a relative path (see Capstone.RootTest for the same
  # rule).
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Capstone.Config
  alias Mix.Tasks.Capstone.Gen.Config, as: GenConfig

  setup do
    dir = Path.join(System.tmp_dir!(), "gen-config-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, dir: dir, path: Path.join(dir, "target.exs")}
  end

  describe "capstone.gen.config" do
    test "writes a target.exs valid against Capstone.Config", %{path: path} do
      capture_io(fn -> GenConfig.run(["--path", path]) end)

      config = path |> File.read!() |> Config.read_string!()

      assert config.schema_version == 1
      assert config.base == :api
      assert config.project.name == "my_app"
      assert config.project.github_org == "acme"
      assert config.plugins == []
    end

    test "refuses to overwrite an existing file without --force", %{path: path} do
      File.write!(path, "already here")

      assert_raise Mix.Error, ~r/already exists.*--force/, fn ->
        GenConfig.run(["--path", path])
      end

      assert File.read!(path) == "already here"
    end

    test "overwrites an existing file when --force is given", %{path: path} do
      File.write!(path, "already here")

      capture_io(fn -> GenConfig.run(["--path", path, "--force"]) end)

      config = path |> File.read!() |> Config.read_string!()
      assert config.base == :api
    end

    test "defaults to target.exs in the current directory", %{dir: dir} do
      File.cd!(dir, fn ->
        capture_io(fn -> GenConfig.run([]) end)
        assert File.exists?("target.exs")
      end)
    end

    test "rejects unknown switches" do
      assert_raise Mix.Error, ~r/unknown switch/, fn ->
        GenConfig.run(["--nonsense"])
      end
    end

    test "rejects positional arguments" do
      assert_raise Mix.Error, ~r/takes no positional arguments/, fn ->
        GenConfig.run(["stray"])
      end
    end
  end
end
