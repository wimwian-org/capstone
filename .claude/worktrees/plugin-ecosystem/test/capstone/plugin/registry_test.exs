defmodule Capstone.Plugin.RegistryTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Capstone.Plugin.Registry

  defp put(dir, filename), do: File.write!(Path.join(dir, filename), "")

  test "default_dir/0 is this app's own priv/plugins" do
    assert Registry.default_dir() == Application.app_dir(:capstone, "priv/plugins")
  end

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
    put(dir, "cache-0.1.0-aaaaaaaaaaaa.tar.gz")
    put(dir, "cache-1.20.3-0.1.0-aaaaaaaaaaaa.tar.gz")

    assert capture_io(fn ->
             assert Registry.resolve!(:cache, "1.20.3", "0.1.0", dir) ==
                      Path.join(dir, "cache-1.20.3-0.1.0-aaaaaaaaaaaa.tar.gz")
           end) =~ "skipping cache-0.1.0-aaaaaaaaaaaa.tar.gz"
  end

  # The right-count-WRONG-CONTENT path, which is the one that used to escape
  # `parse/1` and raise `Version.InvalidVersionError` from deep inside the
  # filter chain — breaking resolution for the whole type rather than for the
  # one stray file.
  @tag :tmp_dir
  test "a malformed Elixir version segment is skipped, not raised on", %{tmp_dir: dir} do
    put(dir, "cache-notaversion-0.1.0-aaaaaaaaaaaa.tar.gz")

    capture_io(fn ->
      assert_raise Mix.Error, ~r/:cache/, fn ->
        Registry.resolve!(:cache, "1.20.3", "0.1.0", dir)
      end
    end)
  end

  @tag :tmp_dir
  test "a malformed capstone version segment is skipped, not raised on", %{tmp_dir: dir} do
    put(dir, "cache-1.20.3-notaversion-aaaaaaaaaaaa.tar.gz")

    capture_io(fn ->
      assert_raise Mix.Error, ~r/:cache/, fn ->
        Registry.resolve!(:cache, "1.20.3", "0.1.0", dir)
      end
    end)
  end

  @tag :tmp_dir
  test "resolution still succeeds when a valid archive sits beside a malformed one",
       %{tmp_dir: dir} do
    put(dir, "cache-notaversion-0.1.0-aaaaaaaaaaaa.tar.gz")
    put(dir, "cache-1.20.3-notaversion-bbbbbbbbbbbb.tar.gz")
    put(dir, "cache-1.20.3-0.1.0-cccccccccccc.tar.gz")

    capture_io(fn ->
      assert Registry.resolve!(:cache, "1.20.3", "0.1.0", dir) ==
               Path.join(dir, "cache-1.20.3-0.1.0-cccccccccccc.tar.gz")
    end)
  end

  @tag :tmp_dir
  test "a malformed archive is skipped with a named Mix.shell().info warning", %{tmp_dir: dir} do
    put(dir, "cache-notaversion-0.1.0-aaaaaaaaaaaa.tar.gz")
    put(dir, "cache-1.20.3-0.1.0-cccccccccccc.tar.gz")

    output =
      capture_io(fn -> Registry.resolve!(:cache, "1.20.3", "0.1.0", dir) end)

    assert output =~ "skipping cache-notaversion-0.1.0-aaaaaaaaaaaa.tar.gz"
    refute output =~ "cache-1.20.3-0.1.0-cccccccccccc.tar.gz"
  end

  describe "retire!/2" do
    @tag :tmp_dir
    test "creates retired.exs when none exists", %{tmp_dir: dir} do
      Registry.retire!("cache-1.20.3-0.1.0-aaaaaaaaaaaa.tar.gz", dir)

      assert File.read!(Path.join(dir, "retired.exs")) =~
               "cache-1.20.3-0.1.0-aaaaaaaaaaaa.tar.gz"
    end

    @tag :tmp_dir
    test "appends to an existing retired.exs without duplicating", %{tmp_dir: dir} do
      Registry.retire!("cache-1.20.3-0.1.0-aaaaaaaaaaaa.tar.gz", dir)
      Registry.retire!("cache-1.20.3-0.1.0-aaaaaaaaaaaa.tar.gz", dir)
      Registry.retire!("openapi-1.20.3-0.1.0-bbbbbbbbbbbb.tar.gz", dir)

      file = Path.join(dir, "retired.exs")
      retired = file |> File.read!() |> Capstone.Source.decode!(file) |> Map.fetch!(:retired)

      assert Enum.sort(retired) == [
               "cache-1.20.3-0.1.0-aaaaaaaaaaaa.tar.gz",
               "openapi-1.20.3-0.1.0-bbbbbbbbbbbb.tar.gz"
             ]
    end

    @tag :tmp_dir
    test "a retired archive is never resolved again", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "cache-1.20.3-0.1.0-aaaaaaaaaaaa.tar.gz"), "")
      Registry.retire!("cache-1.20.3-0.1.0-aaaaaaaaaaaa.tar.gz", dir)

      assert_raise Mix.Error, fn -> Registry.resolve!(:cache, "1.20.3", "0.1.0", dir) end
    end
  end
end
