defmodule Capstone.Plugin.PackageTest do
  use ExUnit.Case, async: true

  alias Capstone.Plugin.Package

  @tag :tmp_dir
  test "packages a derived plugin directory into a deterministic-named archive", %{tmp_dir: tmp} do
    dir = Path.join(tmp, "meta_cache")
    File.mkdir_p!(Path.join(dir, "files"))

    File.write!(
      Path.join(dir, "manifest.exs"),
      "%{name: :cache, version: \"0.1.0\", files: []}\n"
    )

    registry = Path.join(tmp, "registry")
    {:ok, path} = Package.run(:cache, dir, registry)

    assert File.regular?(path)
    assert Path.dirname(path) == registry

    assert Regex.match?(
             ~r/^cache-\d+\.\d+\.\d+-\d+\.\d+\.\d+-[0-9a-f]{12}\.tar\.gz$/,
             Path.basename(path)
           )
  end

  @tag :tmp_dir
  test "packaging identical content twice produces byte-identical archives", %{tmp_dir: tmp} do
    dir = Path.join(tmp, "meta_cache")
    File.mkdir_p!(Path.join(dir, "files"))

    File.write!(
      Path.join(dir, "manifest.exs"),
      "%{name: :cache, version: \"0.1.0\", files: []}\n"
    )

    File.write!(
      Path.join(dir, "files/lib_new_otp_app.ex.eex"),
      "defmodule <%= @module %> do\nend\n"
    )

    {:ok, path1} = Package.run(:cache, dir, Path.join(tmp, "r1"))
    {:ok, path2} = Package.run(:cache, dir, Path.join(tmp, "r2"))

    assert Path.basename(path1) == Path.basename(path2)
    assert :zlib.gunzip(File.read!(path1)) == :zlib.gunzip(File.read!(path2))
  end

  @tag :tmp_dir
  test "a comment-only change to a plugin file changes the sha", %{tmp_dir: tmp} do
    dir1 = Path.join(tmp, "a")
    dir2 = Path.join(tmp, "b")
    File.mkdir_p!(Path.join(dir1, "files"))
    File.mkdir_p!(Path.join(dir2, "files"))
    File.write!(Path.join(dir1, "manifest.exs"), "%{name: :cache}\n")
    File.write!(Path.join(dir2, "manifest.exs"), "%{name: :cache} # a comment\n")

    {:ok, p1} = Package.run(:cache, dir1, Path.join(tmp, "r1"))
    {:ok, p2} = Package.run(:cache, dir2, Path.join(tmp, "r2"))

    refute Path.basename(p1) == Path.basename(p2)
  end
end
