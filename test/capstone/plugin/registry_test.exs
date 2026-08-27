defmodule Capstone.Plugin.RegistryTest do
  use ExUnit.Case, async: true

  alias Capstone.Plugin.Registry

  defp put(dir, filename), do: File.write!(Path.join(dir, filename), "")

  @tag :tmp_dir
  test "resolves the only matching archive", %{tmp_dir: dir} do
    put(dir, "cache-1.20.3-0.1.0-aaaaaaaaaaaa.tar.gz")

    assert Registry.resolve!(:cache, "1.20.3", "0.1.0", dir) ==
             Path.join(dir, "cache-1.20.3-0.1.0-aaaaaaaaaaaa.tar.gz")
  end

  @tag :tmp_dir
  test "matches Elixir by major.minor, not exact patch", %{tmp_dir: dir} do
    put(dir, "cache-1.20.0-0.1.0-aaaaaaaaaaaa.tar.gz")

    assert Registry.resolve!(:cache, "1.20.3", "0.1.0", dir) ==
             Path.join(dir, "cache-1.20.0-0.1.0-aaaaaaaaaaaa.tar.gz")
  end

  @tag :tmp_dir
  test "rejects a different Elixir minor", %{tmp_dir: dir} do
    put(dir, "cache-1.19.0-0.1.0-aaaaaaaaaaaa.tar.gz")

    assert_raise Mix.Error, ~r/cache.*1\.20\.3/, fn ->
      Registry.resolve!(:cache, "1.20.3", "0.1.0", dir)
    end
  end

  @tag :tmp_dir
  test "picks the highest capstone version not exceeding the running one", %{tmp_dir: dir} do
    put(dir, "cache-1.20.3-0.1.0-aaaaaaaaaaaa.tar.gz")
    put(dir, "cache-1.20.3-0.2.0-bbbbbbbbbbbb.tar.gz")
    put(dir, "cache-1.20.3-0.9.0-cccccccccccc.tar.gz")

    assert Registry.resolve!(:cache, "1.20.3", "0.2.0", dir) ==
             Path.join(dir, "cache-1.20.3-0.2.0-bbbbbbbbbbbb.tar.gz")
  end

  @tag :tmp_dir
  test "excludes a retired archive", %{tmp_dir: dir} do
    put(dir, "cache-1.20.3-0.1.0-aaaaaaaaaaaa.tar.gz")
    put(dir, "cache-1.20.3-0.2.0-bbbbbbbbbbbb.tar.gz")

    File.write!(
      Path.join(dir, "retired.exs"),
      "%{retired: [\"cache-1.20.3-0.2.0-bbbbbbbbbbbb.tar.gz\"]}\n"
    )

    assert Registry.resolve!(:cache, "1.20.3", "0.2.0", dir) ==
             Path.join(dir, "cache-1.20.3-0.1.0-aaaaaaaaaaaa.tar.gz")
  end

  @tag :tmp_dir
  test "raises naming the type and both versions when every candidate is eliminated",
       %{tmp_dir: dir} do
    put(dir, "openapi-1.20.3-0.1.0-aaaaaaaaaaaa.tar.gz")

    assert_raise Mix.Error, ~r/:cache.*1\.20\.3.*0\.1\.0/, fn ->
      Registry.resolve!(:cache, "1.20.3", "0.1.0", dir)
    end
  end

  @tag :tmp_dir
  test "a filename that doesn't parse is skipped, not raised on", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "not-a-plugin-archive"), "")
    put(dir, "cache-1.20.3-0.1.0-aaaaaaaaaaaa.tar.gz")

    assert Registry.resolve!(:cache, "1.20.3", "0.1.0", dir) ==
             Path.join(dir, "cache-1.20.3-0.1.0-aaaaaaaaaaaa.tar.gz")
  end
end
