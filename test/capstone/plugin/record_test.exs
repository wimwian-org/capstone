defmodule Capstone.Plugin.RecordTest do
  # async: false — copies real trees under priv/meta, and the recorded origin is
  # resolved against the current working directory.
  use ExUnit.Case, async: false

  alias Capstone.Config
  alias Capstone.Factory
  alias Capstone.Hash
  alias Capstone.Manifest
  alias Capstone.Plugin.Apply
  alias Capstone.Plugin.Record
  alias Capstone.Root

  @baseline "priv/meta/baseline_otp"
  @plugin "priv/meta/meta_cache"
  @owned "lib/new_otp_app/cache.ex"
  @positional "lib/new_otp_app.ex"

  setup do
    dir = Path.join(System.tmp_dir!(), "record-#{System.unique_integer([:positive])}")
    File.cp_r!(@baseline, dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, dir: dir, target: Root.new!(dir)}
  end

  # `base: :api` here, not the umbrella's `:otp` -- this package's own
  # Capstone.Config only accepts :api/:web/:both. A literal target.exs
  # rather than a :config_map factory build, since that factory is shaped
  # for the excluded 14-module schema this package doesn't have.
  defp declare!(target, attrs \\ [base: :api]) do
    base = Keyword.get(attrs, :base, :api)

    File.write!(
      Root.path(target, "target.exs"),
      ~s"""
      %{
        schema_version: 1,
        base: #{inspect(base)},
        plugins: [],
        project: [name: "new_otp_app", github_org: "acme"]
      }
      """
    )
  end

  defp entry(target), do: hd(Manifest.read!(target).plugins)

  defp hash_of(target, path) do
    Enum.find_value(entry(target).files, fn file -> if file.path == path, do: file.hash end)
  end

  describe "a target that declares itself" do
    test "gets a plugin.exs Manifest.read!/1 round-trips", %{dir: dir, target: target} do
      declare!(target)

      {:ok, plugin} = Apply.run(@plugin, dir)

      manifest = Manifest.read!(target)
      # `base` is READ from target.exs, never inferred: a manifest that
      # asserts a fact nobody verified is worse than no manifest, because the
      # update flow trusts it.
      assert manifest.base == :api
      # 2 since `capstone_version` replaced `sv_ex_version`: a required key
      # changing name is a file-format change, and Capstone.Manifest owns the
      # number Record stamps.
      assert manifest.schema_version == Capstone.Manifest.schema_version()
      assert manifest.capstone_version == List.to_string(Application.spec(:capstone, :vsn))
      assert [recorded] = manifest.plugins
      assert recorded.name == :cache
      assert recorded.version == plugin.version
      # Repo-relative, never absolute — SDD 4.1 defect 13.
      assert recorded.origin == {:path, @plugin}
      assert length(recorded.files) == length(plugin.files)
    end

    test "base is READ from target.exs, not the suite's shared :otp default",
         %{dir: dir, target: target} do
      # Every other test in this file declares base: :api (declare!/2's
      # default) — so `base: Config.read_string!(source).base` in record.ex
      # could be replaced with a hardcoded :api and the whole suite would
      # stay green. This is the one test that would catch it.
      declare!(target, base: :web)

      {:ok, _component} = Apply.run(@plugin, dir)

      assert Manifest.read!(target).base == :web
    end

    test "records the mode the plugin declared, :manual included", %{dir: dir, target: t} do
      declare!(t)

      {:ok, _component} = Apply.run(@plugin, dir)

      modes = Map.new(entry(t).files, &{&1.path, {&1.mode, &1.key}})
      assert modes[@owned] == {:sole_owner, nil}
      assert modes["README.md"] == {:contributes, :cache_readme}
      assert modes[@positional] == {:manual, :cache_app}
    end

    test "each recorded hash is Hash.content_hash/2 over the written file", %{dir: d, target: t} do
      declare!(t)

      {:ok, _component} = Apply.run(@plugin, d)

      for file <- entry(t).files do
        contents = File.read!(Root.path(t, file.path))
        assert file.hash == Hash.content_hash(contents, file.path)
      end
    end

    test "config_digest is Hash.content_hash/2 over target.exs", %{dir: dir, target: target} do
      # Hash, not a raw sha256, and deliberately so: a comment added to
      # target.exs is not a change of intent and must not read as one when the
      # update flow compares digests.
      declare!(target)

      {:ok, _component} = Apply.run(@plugin, dir)

      file = Root.path(target, "target.exs")
      assert Manifest.read!(target).config_digest == Hash.content_hash(File.read!(file), file)

      assert Hash.content_hash("# a note\n" <> File.read!(file), file) ==
               Manifest.read!(target).config_digest
    end

    test "a comment in a recorded file does not change its hash, but an edit does",
         %{dir: dir, target: target} do
      # THE property SDD 4.1 says Fireside got wrong, and the entire reason
      # Capstone.Hash exists: a `# credo:disable-for-next-line` must never lock
      # a project out of updates, while real code changes must still show.
      declare!(target)
      {:ok, _component} = Apply.run(@plugin, dir)

      original = File.read!(Root.path(target, @owned))
      recorded = hash_of(target, @owned)

      assert Hash.content_hash("# credo:disable-for-next-line\n" <> original, @owned) == recorded
      refute Hash.content_hash(original <> "\ndefmodule Extra do\nend\n", @owned) == recorded
    end

    test "applying twice leaves exactly one entry", %{dir: dir, target: target} do
      # Manifest.encode!/1 rejects duplicate plugin names, so an append-only
      # recorder would fail its own validator on the second run.
      declare!(target)

      {:ok, _} = Apply.run(@plugin, dir)
      {:ok, _} = Apply.run(@plugin, dir)

      assert [_one] = Manifest.read!(target).plugins
    end

    test "records the dependencies it installed into the target", %{dir: dir, target: target} do
      # The KNOWN INCOMPLETENESS this closes. Apply writes a plugin's deps
      # into the target's mix.exs, and nothing recorded WHICH plugin put
      # them there — so an update flow could not attribute a dependency, nor
      # tell that a user had hand-edited it afterwards.
      declare!(target)

      {:ok, _} = Apply.run(@plugin, dir)

      assert entry(target).deps == [~s|{:nebulex, "~> 2.6"}|]
    end

    test "records no aliases or project keys when the plugin contributes none",
         %{dir: dir, target: target} do
      # Empty stays empty rather than absent: the field is always present in a
      # recorded entry, because "this plugin added nothing" and "nobody
      # asked" are different claims and only the first is a record.
      declare!(target)

      {:ok, _} = Apply.run(@plugin, dir)

      assert entry(target).aliases == []
      assert entry(target).project == []
    end

    test "re-applying refreshes applied_at", %{dir: dir, target: target} do
      declare!(target)
      {:ok, _} = Apply.run(@plugin, dir)
      first = entry(target).applied_at
      Process.sleep(1)

      {:ok, _} = Apply.run(@plugin, dir)

      assert entry(target).applied_at > first
    end

    test "an existing manifest keeps its other plugins and its generated_at",
         %{dir: dir, target: target} do
      # generated_at is a fact about the PAST. A recorder rewriting it would
      # erase the only record of when the project was laid down — while base and
      # config_digest describe the CURRENT target.exs and are recomputed.
      declare!(target)
      Manifest.write!(target, Factory.build(:manifest))
      previous = Manifest.read!(target)

      {:ok, _component} = Apply.run(@plugin, dir)

      recorded = Manifest.read!(target)
      names = Enum.map(recorded.plugins, & &1.name)
      assert :cache in names
      for plugin <- previous.plugins, do: assert(plugin.name in names)
      assert recorded.generated_at == previous.generated_at
      # The factory manifest says :web; target.exs says :api, and the file wins.
      assert previous.base == :web
      assert recorded.base == :api
    end

    test "a file left conflict-marked is recorded as text, not as Elixir", %{dir: d, target: t} do
      # Strip the anchor's distinguishing context so the :manual hunk marks
      # instead of placing. The file is then not valid Elixir at all, the parser
      # refuses it, and recording must still produce a hash for a file apply has
      # already written. The marker is read off DISK rather than reported by
      # apply, because a second apply short-circuits on the marker already being
      # there and would report nothing.
      declare!(t)
      File.write!(Path.join(d, @positional), "defmodule NewOtpApp do\nend\n")

      {:ok, _component} = Apply.run(@plugin, d)

      marked = File.read!(Path.join(d, @positional))
      assert marked =~ Apply.marker_prefix(:cache_app)
      assert_raise SyntaxError, fn -> Hash.content_hash(marked, @positional) end
      assert hash_of(t, @positional) == Hash.text_hash(marked)
    end

    test "a marker under a DIFFERENT key still hashes as text, not a crash",
         %{dir: dir, target: target} do
      # Pre-seed a marker for a key that is NOT this entry's own key
      # (:cache_app), the anchor left otherwise untouched so :manual places
      # cleanly. Guards hash/3: a marker left under any key must route to the
      # text hash, because a marker under a foreign key makes the file
      # unparseable too. Assembled rather than written whole, so this file
      # does not itself carry a marker for mix capstone.check to find.
      declare!(target)
      foreign = String.duplicate("<", 7) <> " capstone: other_key\n"
      file = Path.join(dir, @positional)
      File.write!(file, File.read!(file) <> foreign)

      {:ok, _component} = Apply.run(@plugin, dir)

      marked = File.read!(file)
      assert marked =~ Apply.marker_prefix("")
      refute marked =~ Apply.marker_prefix(:cache_app)
      assert_raise SyntaxError, fn -> Hash.content_hash(marked, @positional) end
      assert hash_of(target, @positional) == Hash.text_hash(marked)
    end

    test "tracked?/1 is true", %{dir: dir, target: target} do
      declare!(target)

      assert Record.tracked?(dir)
    end

    test "a malformed target.exs raises before Apply writes anything",
         %{dir: dir, target: target} do
      # The pre-flight this guards: without it, a bad target.exs is only
      # discovered by Record.run/4, AFTER every file has already been written
      # and mix.exs rewritten — so a user sees a config error from a task
      # named "apply" and reasonably, wrongly, concludes the apply failed.
      File.write!(Root.path(target, "target.exs"), "%{}\n")

      assert_raise Config.Error, fn -> Apply.run(@plugin, dir) end
      refute File.exists?(Path.join(dir, @owned))
    end
  end

  describe "an :origin opt" do
    test "is recorded verbatim instead of the computed :path", %{dir: dir, target: target} do
      # Apply.run/2 first, exactly as every other test here, so every file the
      # plugin owns already exists on disk. Record.run/5 is then called a
      # second time directly, standing in for what Apply.run/3 does
      # internally, to isolate the override on the recorder itself.
      declare!(target)
      {:ok, plugin} = Apply.run(@plugin, dir)
      names = Apply.names(dir)

      Record.run(@plugin, dir, plugin, names,
        origin: {:registry, "cache-1.20.3-0.1.0-a3f9c21b0e77.tar.gz"}
      )

      assert entry(target).origin == {:registry, "cache-1.20.3-0.1.0-a3f9c21b0e77.tar.gz"}
    end

    test "is not consulted when absent, computing the :path origin as before",
         %{dir: dir, target: target} do
      declare!(target)

      {:ok, _plugin} = Apply.run(@plugin, dir)

      assert entry(target).origin == {:path, @plugin}
    end
  end

  describe "a target that does not" do
    test "is installed, and records nothing", %{dir: dir, target: target} do
      {:ok, _component} = Apply.run(@plugin, dir)

      assert File.exists?(Path.join(dir, @owned))
      refute File.exists?(Manifest.path(target))
      refute Record.tracked?(dir)
    end
  end

  describe "this repository's own target.exs" do
    # Not built from a fixture: this is the real, checked-in target.exs at the
    # repo root, read through the real Config.read/1 that a live
    # `mix capstone.*` invocation would use. Every other Config-shaped test in
    # this suite exercises either a synthetic struct or a hand-authored
    # fixture -- this is the one place a real generated target.exs still gets
    # read end to end.
    test "reports the placeholder name and github_org as invalid" do
      path = Path.join(File.cwd!(), "target.exs")
      assert File.exists?(path)

      assert Config.read(path) ==
               {:error,
                [
                  {:invalid_type, [:project, :name],
                   "a lowercase OTP app name matching ~r/^[a-z][a-z0-9_]*$/", ""},
                  {:invalid_type, [:project, :github_org], "non-empty String.t()", ""}
                ]}
    end
  end
end
