defmodule Capstone.ManifestTest do
  use ExUnit.Case, async: false

  alias Capstone.Factory
  alias Capstone.Hash
  alias Capstone.Manifest
  alias Capstone.Manifest.FileEntry
  alias Capstone.ProjectFixture
  alias Capstone.Root
  alias Capstone.Source

  @top_keys [
    :base,
    :plugins,
    :config_digest,
    :generated_at,
    :schema_version,
    :capstone_version
  ]
  @component_keys [:applied_at, :files, :name, :origin, :version]
  @file_keys [:hash, :mode, :path]

  defp tmp_dir do
    path = Path.join(System.tmp_dir!(), "capstone-manifest-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end

  setup do
    original = File.cwd!()
    on_exit(fn -> File.cd!(original) end)
    :ok
  end

  for variety <- [:broken_syntax, :broken_semantics] do
    test "write! -> read! round-trips against a #{variety} target" do
      target = Root.new!(ProjectFixture.create!(tmp_dir(), unquote(variety)))
      manifest = Factory.build(:manifest)

      # Both origin shapes have to be in the corpus: the relative-path branch of
      # the origin check is otherwise reachable only by the test that asserts an
      # ABSOLUTE one raises, which never runs it.
      origins = Enum.map(manifest.plugins, &elem(&1.origin, 0))
      assert :hex in origins and :path in origins

      assert Manifest.write!(target, manifest) == :ok
      assert Manifest.read!(target) == manifest

      # The byte-stability half: encoding what we read reproduces the file.
      assert Manifest.encode!(Manifest.read!(target)) == File.read!(Manifest.path(target))
    end
  end

  test "read!/1 returns identical data regardless of cwd" do
    dir = ProjectFixture.create!(tmp_dir(), :broken_syntax)
    target = Root.new!(dir)
    Manifest.write!(target, Factory.build(:manifest))
    expected = Manifest.read!(target)

    for cwd <- [File.cwd!(), dir, "/"] do
      File.cd!(cwd)
      assert Manifest.read!(target) == expected
    end
  end

  test "encode!/1 is byte-identical when plugins are supplied in reversed order" do
    # sort_maps sorts map KEYS only — list order is ours.
    plugins = Factory.build_list(3, :manifest_component)
    forward = Factory.build(:manifest, plugins: plugins)
    reversed = Factory.build(:manifest, plugins: Enum.reverse(plugins))

    assert Manifest.encode!(forward) == Manifest.encode!(reversed)
  end

  test "encode!/1 is byte-identical when a plugin's files are supplied in reversed order" do
    # The second list-ordering surface. Nothing else reaches it: every other
    # test's files arrive already sorted, so dropping the file sort leaves the
    # whole suite green.
    files = Factory.build(:manifest_component).files
    forward = one_component_manifest(name: :valkey, files: files)
    reversed = one_component_manifest(name: :valkey, files: Enum.reverse(files))

    assert Manifest.encode!(forward) == Manifest.encode!(reversed)
  end

  test "an encoded :sole_owner entry contains no key: field at all" do
    # A nil :key is OMITTED, not encoded — matching SDD 8.2 exactly.
    entry = Factory.build(:file_entry, mode: :sole_owner)
    manifest = one_component_manifest(files: [entry])

    refute Manifest.encode!(manifest) =~ "key:"
  end

  test "mode and key exclusivity is enforced" do
    cases = [
      {%{mode: :contributes, key: nil}, ~r/:contributes requires/},
      {%{mode: :sole_owner, key: :x}, ~r/:sole_owner.*must not/},
      {%{mode: :seed, key: :x}, ~r/:seed.*must not/},
      {%{mode: :overwritable, key: nil}, ~r/:sole_owner.*:contributes.*:seed/}
    ]

    for {attrs, message} <- cases do
      entry = struct(FileEntry, Map.merge(Map.from_struct(Factory.build(:file_entry)), attrs))
      manifest = one_component_manifest(files: [entry])

      assert_raise Manifest.InvalidError, message, fn -> Manifest.encode!(manifest) end
    end
  end

  test "an absolute path origin raises" do
    manifest = one_component_manifest(origin: {:path, "/abs/path"})

    assert_raise Manifest.InvalidError, ~r/absolute/, fn -> Manifest.encode!(manifest) end
  end

  test "a malformed origin raises" do
    for origin <- [{:hex, "x"}, {:hex, "x", 3}, {:path, 3}, :hex] do
      manifest = one_component_manifest(origin: origin)

      assert_raise Manifest.InvalidError, ~r/origin must be/, fn ->
        Manifest.encode!(manifest)
      end
    end
  end

  test "a non-semver plugin version raises" do
    for version <- ["not-a-version", 3] do
      manifest = one_component_manifest(version: version)

      assert_raise Manifest.InvalidError, ~r/semver/, fn -> Manifest.encode!(manifest) end
    end
  end

  test "hashes and config_digest must be sha256:<64 lowercase hex>" do
    # `3` is not a stylistic fourth case: every binary here is rejected by the
    # regex, so the non-binary clause is unreachable without it.
    for bad <- [
          "sha256:" <> String.duplicate("A", 64),
          "sha256:abc",
          String.duplicate("a", 64),
          3
        ] do
      manifest = Factory.build(:manifest, config_digest: bad)
      assert_raise Manifest.InvalidError, ~r/sha256/, fn -> Manifest.encode!(manifest) end

      entry = Factory.build(:file_entry, hash: bad)
      files = one_component_manifest(files: [entry])
      assert_raise Manifest.InvalidError, ~r/sha256/, fn -> Manifest.encode!(files) end
    end
  end

  test "generated_at and applied_at must be ISO8601 UTC strings that round-trip" do
    # "+00:00" is offset zero and parses, but re-encoding it would not reproduce
    # the file's bytes, so it is not a value this format accepts.
    bad_values = [
      "not-a-date",
      "2026-08-11 00:00:00",
      "2026-08-11T00:00:00+00:00",
      ~U[2026-08-11 00:00:00Z]
    ]

    for bad <- bad_values do
      manifest = Factory.build(:manifest, generated_at: bad)

      assert_raise Manifest.InvalidError, ~r/generated_at.*ISO8601/, fn ->
        Manifest.encode!(manifest)
      end

      applied = one_component_manifest(applied_at: bad)

      assert_raise Manifest.InvalidError, ~r/applied_at.*ISO8601/, fn ->
        Manifest.encode!(applied)
      end
    end
  end

  test "base must name a supported base, and the rejected value is named" do
    manifest = Factory.build(:manifest, base: :cli)

    assert_raise Manifest.InvalidError,
                 ~r/base must be one of \[:otp, :api, :web\], got: :cli/,
                 fn -> Manifest.encode!(manifest) end
  end

  test "every supported base round-trips" do
    for base <- [:otp, :api, :web] do
      encoded = Manifest.encode!(Factory.build(:manifest, base: base))

      assert Manifest.decode!(encoded, "plugin.exs").base == base
    end
  end

  # A test asserting "every base Capstone.Config resolves, Manifest can also
  # record" existed here in capstone_umbrella, built on Capstone.Config.decode!/2
  # against a :config_map fixture shaped for the umbrella's 14-module Config
  # schema (bases :otp/:api/:web, decode!/2). This package kept its own,
  # differently-shaped Capstone.Config (bases :api/:web/:both, no decode!/2) --
  # dropped rather than adapted, since porting it would mean reintroducing the
  # excluded schema's vocabulary just for this one assertion.

  test "duplicate plugin names raise" do
    duplicate = Factory.build(:manifest_component, name: :valkey)
    manifest = Factory.build(:manifest, plugins: [duplicate, duplicate])

    assert_raise Manifest.InvalidError, ~r/duplicate/, fn -> Manifest.encode!(manifest) end
  end

  test "an unknown schema_version and an unknown top-level key each raise" do
    target = Root.new!(ProjectFixture.create!(tmp_dir(), :valid))

    # 3, not 2: `capstone_version` replacing `sv_ex_version` is a file-format
    # change, so the written version moved to 2 and 1 stayed readable. The probe
    # has to name a version nothing supports or it stops measuring anything.
    for map <- [%{schema_version: 3}, %{surprise: true}] do
      File.write!(Manifest.path(target), Source.encode!(Map.merge(manifest_data(), map)))
      assert_raise Manifest.InvalidError, fn -> Manifest.read!(target) end
    end
  end

  describe "the sv_ex-era plugin.exs" do
    test "is refused with a message naming the rename, not 'unknown key'" do
      # `validate_keys!/2` rejects an undeclared key outright, so a plugin.exs
      # written by SvEx does not degrade -- it refuses to read. No migration is
      # written, but the refusal names what happened rather than reporting a key
      # nobody chose.
      target = Root.new!(ProjectFixture.create!(tmp_dir(), :valid))

      data =
        manifest_data()
        |> Map.delete(:capstone_version)
        |> Map.put(:sv_ex_version, "0.9.0")

      File.write!(Manifest.path(target), Source.encode!(data))

      assert_raise Manifest.InvalidError,
                   ~r/sv_ex_version was renamed to capstone_version/,
                   fn -> Manifest.read!(target) end
    end

    test "schema_version 1 still decodes, so the rename is what the message names" do
      # If 1 had been dropped from the supported list, an sv_ex file would be
      # refused for its VERSION and the renamed key would never be reached --
      # the worse error, and the reason the old version stays readable.
      target = Root.new!(ProjectFixture.create!(tmp_dir(), :valid))
      data = Map.put(manifest_data(), :schema_version, 1)

      File.write!(Manifest.path(target), Source.encode!(data))

      assert %Manifest{schema_version: 1} = Manifest.read!(target)
    end
  end

  test "a missing key raises naming itself, at every level of the file" do
    # `Map.fetch!/2`'s KeyError would be a different exception class from the
    # one Capstone.Config raises for the same edit to target.exs, and both
    # files are hand-editable by whoever the generator wrote them for.
    target = Root.new!(ProjectFixture.create!(tmp_dir(), :valid))

    deletions =
      Enum.map(@top_keys, &{&1, fn data -> Map.delete(data, &1) end}) ++
        Enum.map(@component_keys, &{&1, fn data -> drop_component_key(data, &1) end}) ++
        Enum.map(@file_keys, &{&1, fn data -> drop_file_key(data, &1) end})

    for {key, delete} <- deletions do
      File.write!(Manifest.path(target), Source.encode!(delete.(manifest_data())))

      assert_raise Manifest.InvalidError, ~r/plugin\.exs: #{key} is required/, fn ->
        Manifest.read!(target)
      end
    end
  end

  test "read!/1 raises File.Error naming plugin.exs when absent" do
    target = Root.new!(ProjectFixture.create!(tmp_dir(), :valid))

    assert_raise File.Error, ~r/plugin\.exs/, fn -> Manifest.read!(target) end
  end

  test "write!/2 never mints a timestamp" do
    manifest = Factory.build(:manifest, generated_at: "2026-08-11T00:00:00Z")

    assert Manifest.encode!(manifest) == Manifest.encode!(manifest)

    refute File.read!("lib/capstone/manifest.ex") =~
             ~r/(DateTime|NaiveDateTime)\.utc_now|System\.system_time/
  end

  test "a hash read back out of the manifest survives reindentation and a comment" do
    # End-to-end with Capstone.Hash — the whole point of step 4. The hash makes
    # the round trip through the FILE, so this fails if either module drifts.
    target = Root.new!(ProjectFixture.create!(tmp_dir(), :broken_syntax))
    %{source: source} = Factory.build(:elixir_source)
    path = "lib/a.ex"
    entry = Factory.build(:file_entry, path: path, hash: Hash.content_hash(source, path))

    Manifest.write!(target, one_component_manifest(files: [entry]))
    [%{files: [stored]}] = Manifest.read!(target).plugins

    edited = "# credo:disable-for-next-line\n" <> String.replace(source, "  ", "    ")
    assert Hash.content_hash(edited, path) == stored.hash
  end

  @tag :determinism
  test "encode!/1 is byte-identical across two processes with reversed atom order" do
    probe = "test/support/determinism_probe.exs"
    ebin = Path.join(Mix.Project.build_path(), "lib/capstone/ebin")

    # Status and digest SHAPE are asserted before the two runs are compared:
    # with a bad -pa the probe dies on stderr, System.cmd/3 does not raise, and
    # both directions return "" — so a status-blind comparison passes while
    # proving nothing. That is the F4 signature.
    run = fn direction ->
      {output, status} =
        System.cmd("elixir", ["-pa", ebin, probe, direction, "manifest"], stderr_to_stdout: true)

      trimmed = String.trim(output)

      assert status == 0, "probe #{direction} exited #{status}:\n#{output}"
      assert trimmed =~ ~r/\A[0-9a-f]{64}\z/, "probe #{direction} printed no digest:\n#{output}"

      trimmed
    end

    assert run.("fwd") == run.("rev")
  end

  describe "the :manual ownership mode" do
    alias Capstone.Manifest.FileEntry

    @digest "sha256:" <> String.duplicate("a", 64)

    test "is accepted and requires a key, like :contributes" do
      entry = %FileEntry{
        path: "lib/app/application.ex",
        mode: :manual,
        key: :valkey_child,
        hash: @digest
      }

      assert FileEntry.validate!(entry) == :ok
    end

    test "without a key it is rejected" do
      entry = %FileEntry{path: "lib/app/application.ex", mode: :manual, key: nil, hash: @digest}

      assert_raise Capstone.Manifest.InvalidError, ~r/requires a :key/, fn ->
        FileEntry.validate!(entry)
      end
    end
  end

  defp one_component_manifest(attrs) do
    Factory.build(:manifest, plugins: [Factory.build(:manifest_component, attrs)])
  end

  defp manifest_data do
    Source.decode!(Manifest.encode!(Factory.build(:manifest)), "plugin.exs")
  end

  defp drop_component_key(data, key) do
    %{data | plugins: Enum.map(data.plugins, &Map.delete(&1, key))}
  end

  defp drop_file_key(data, key) do
    plugins =
      Enum.map(data.plugins, fn plugin ->
        %{plugin | files: Enum.map(plugin.files, &Map.delete(&1, key))}
      end)

    %{data | plugins: plugins}
  end
end
