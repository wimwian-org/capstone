defmodule Mix.Tasks.Capstone.Baseline.RecordTest do
  # async: false — the task rewrites priv/baselines.exs inside the repo working
  # tree and writes archives to the repo root, which Capstone.BaselineTest reads.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Capstone.Baseline

  setup do
    manifest = File.read!("priv/baselines.exs")
    before = MapSet.new(Path.wildcard("*.tar.gz"))

    on_exit(fn ->
      File.write!("priv/baselines.exs", manifest)

      "*.tar.gz"
      |> Path.wildcard()
      |> Enum.reject(&MapSet.member?(before, &1))
      |> Enum.each(&File.rm!/1)
    end)

    {:ok, manifest: manifest}
  end

  test "writes the manifest and one archive per baseline, reporting each", %{manifest: manifest} do
    output = capture_io(fn -> Mix.Tasks.Capstone.Baseline.Record.run([]) end)

    assert output =~ "wrote priv/baselines.exs"
    # The archive name leads with the manifest key and the release version, so
    # a directory of release assets is readable without opening any of them.
    # `\1` is what makes each line prove its OWN name rather than merely that
    # some well-formed name appeared somewhere in the output.
    assert output =~ ~r/(api): 30 files -> \1_\d+\.\d+\.\d+_[0-9a-f]{8}\.tar\.gz/
    assert output =~ ~r/(otp): 7 files -> \1_\d+\.\d+\.\d+_[0-9a-f]{8}\.tar\.gz/
    assert output =~ ~r/(cache): 8 files -> \1_\d+\.\d+\.\d+_[0-9a-f]{8}\.tar\.gz/
    assert output =~ ~r/(openapi): 34 files -> \1_\d+\.\d+\.\d+_[0-9a-f]{8}\.tar\.gz/
    assert output =~ ~r/(prod_image_api): 37 files -> \1_\d+\.\d+\.\d+_[0-9a-f]{8}\.tar\.gz/

    # The version in the name is THIS release's, not a literal anybody has to
    # remember to bump -- .version moves on every commit.
    assert output =~ "_#{Mix.Project.config()[:version]}_"

    # Recording a tree that has not changed must reproduce the checked-in bytes.
    # This is the whole point of the deterministic encoder and the pinned tar
    # metadata: a task that churned the manifest would make every run a diff.
    assert File.read!("priv/baselines.exs") == manifest
  end

  test "each recorded archive exists and matches its recorded sha" do
    capture_io(fn -> Mix.Tasks.Capstone.Baseline.Record.run([]) end)

    version = Mix.Project.config()[:version]

    for {key, entry} <- Baseline.read!("priv/baselines.exs") do
      archive = Baseline.archive_name(key, version, entry.archive_sha256)
      assert File.exists?(archive)

      {:ok, outer} = :erl_tar.extract({:binary, :zlib.gunzip(File.read!(archive))}, [:memory])
      outer = Map.new(outer)
      inner = Map.fetch!(outer, ~c"baseline.tar")

      assert Base.encode16(:crypto.hash(:sha256, inner), case: :lower) == entry.archive_sha256
      assert Map.fetch!(outer, ~c"baseline.sha256") == "#{entry.archive_sha256}  baseline.tar\n"
    end
  end
end
