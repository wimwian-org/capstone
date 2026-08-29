defmodule Capstone.BaselineTest do
  # async: false — two tests below rewrite files inside the repo working tree.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Capstone.Baseline
  alias Capstone.Factory
  alias Mix.Tasks.Capstone.Baseline.Compose

  test "normalise_secrets/1 is idempotent" do
    %{source: source} = Factory.build(:phx_config_source)
    once = Baseline.normalise_secrets(source)
    assert Baseline.normalise_secrets(once) == once
  end

  test "normalise_secrets/1 handles values containing + and / and leading /" do
    %{source: source} =
      Factory.build(:phx_config_source, secret: "/6BqrGihxYHaWA+Mx" <> String.duplicate("a", 47))

    # BOTH placeholders, not just the one this test is named for: the fixture's
    # salt carries a `+` and a `/` too, and with only the SECRET_KEY_BASE
    # assertion, deleting `signing_salt` from `@secret_keys` survives the entire
    # suite — every other test reads the ALREADY-normalised checked-in bytes.
    assert Baseline.normalise_secrets(source) =~ "<<SECRET_KEY_BASE>>"
    assert Baseline.normalise_secrets(source) =~ "<<SIGNING_SALT>>"
  end

  test "normalise_secrets/1 anchors on the key name and leaves an unrelated 64-char string alone" do
    source = ~s|other: "#{String.duplicate("z", 64)}"\n|
    assert Baseline.normalise_secrets(source) == source
  end

  test "tree/1 prunes .git, deps and _build and returns relative paths" do
    %{path: path} = Factory.build(:baseline_tree)
    paths = path |> Baseline.tree() |> Map.keys()

    refute Enum.any?(paths, &(&1 =~ ~r{^(\.git|deps|_build)/}))
    refute Enum.any?(paths, &String.starts_with?(&1, "/"))

    # Both refutes above are satisfied by an empty tree. The dotfile is the
    # positive control, and it is the one `match_dot: false` would drop.
    assert ".formatter.exs" in paths
    assert "lib/app.ex" in paths
  end

  test "tree/1 prunes node_modules" do
    # Measured: a meta project with its assets installed reported 38,189 of
    # 38,215 added files as node_modules, and derive then tried to template a
    # binary out of one. Installed packages are a build artifact exactly as
    # deps/ and _build/ are, and belong in the same list.
    %{path: path} = Factory.build(:baseline_tree)
    File.mkdir_p!(Path.join(path, "assets/node_modules/svelte"))
    File.write!(Path.join(path, "assets/node_modules/svelte/index.js"), "export {}\n")

    paths = path |> Baseline.tree() |> Map.keys()

    refute Enum.any?(paths, &String.contains?(&1, "node_modules"))
    # Positive control: a sibling under assets/ is NOT pruned.
    assert ".formatter.exs" in paths
  end

  test "tree/1 prunes build output and the lockfile" do
    # Measured on the web plugin: mix.lock, priv/static/.vite/manifest.json
    # and the hashed bundle were all captured as :sole_owner entries. A
    # plugin shipping mix.lock would OVERWRITE the target project's whole
    # dependency resolution, which is R6's first-order violation; the rest is
    # build output that apply has no business writing.
    %{path: path} = Factory.build(:baseline_tree)
    File.write!(Path.join(path, "mix.lock"), "%{}\n")
    File.mkdir_p!(Path.join(path, "priv/static/assets"))
    File.mkdir_p!(Path.join(path, "priv/static/.vite"))
    File.write!(Path.join(path, "priv/static/assets/app-abc.js"), "x\n")
    File.write!(Path.join(path, "priv/static/.vite/manifest.json"), "{}\n")
    File.write!(Path.join(path, "priv/static/favicon.ico"), "icon\n")

    paths = path |> Baseline.tree() |> Map.keys()

    refute "mix.lock" in paths
    refute Enum.any?(paths, &String.starts_with?(&1, "priv/static/assets/"))
    refute Enum.any?(paths, &String.starts_with?(&1, "priv/static/.vite/"))
    # Positive control: priv/static itself is source, and `assets/` at the ROOT
    # is the Svelte tree, not build output.
    assert "priv/static/favicon.ico" in paths
  end

  test "digest/1 is stable across 5 calls and changes when any file changes" do
    %{path: path} = Factory.build(:baseline_tree)
    assert [_one] = 1..5 |> Enum.map(fn _ -> Baseline.digest(path) end) |> Enum.uniq()

    before = Baseline.digest(path)
    File.write!(Path.join(path, "README.md"), "changed")
    refute Baseline.digest(path) == before
  end

  test "an added comment in a baseline file IS drift" do
    # Negative control: Baseline must NOT share Capstone.Hash's comment-stripping
    # normaliser. The manifest hash must IGNORE an added comment; the baseline
    # check must TREAT it as drift. Two normalisers, deliberately opposite.
    file = "priv/meta/baseline_api/mix.exs"
    original = File.read!(file)
    on_exit(fn -> File.write!(file, original) end)

    before = Baseline.digest("priv/meta/baseline_api")
    File.write!(file, original <> "\n# drift\n")
    refute Baseline.digest("priv/meta/baseline_api") == before
  end

  test "the recorded files and tree_digest match the checked-in baselines" do
    # Offline, no generator — runs on every commit.
    for {_key, entry} <- Baseline.read!("priv/baselines.exs") do
      assert Baseline.digest(entry.path) == entry.tree_digest

      # Per-file, via assert_same_tree/2, so a drift failure NAMES the file
      # instead of printing two opaque digests across 45 files.
      assert_same_tree(entry.files, Baseline.tree(entry.path))
    end
  end

  test "exactly the recorded files are normalised, and no others" do
    for {_key, entry} <- Baseline.read!("priv/baselines.exs") do
      secrets = for {:secret, file, _key} <- Map.get(entry, :normalisations, []), do: file

      changed =
        entry.path
        |> Baseline.tree()
        |> Map.keys()
        |> Enum.filter(
          &(File.read!(Path.join(entry.path, &1)) =~ ~r/<<(SECRET_KEY_BASE|SIGNING_SALT)>>/)
        )

      assert Enum.sort(changed) == Enum.sort(secrets), "#{entry.path} normalisations drifted"
    end
  end

  test "the api baseline carries no html or asset pipeline" do
    # Offline, and the property the whole composition argument rests on: the
    # deletion targets the Svelte layer would otherwise have to dismantle do not
    # exist here in the first place.
    paths = "priv/meta/baseline_api" |> Baseline.tree() |> Map.keys()
    mix_exs = File.read!("priv/meta/baseline_api/mix.exs")

    refute Enum.any?(paths, &String.starts_with?(&1, "assets/"))
    refute Enum.any?(paths, &(&1 =~ ~r/core_components\.ex|page_controller\.ex|page_html/))
    refute mix_exs =~ ":esbuild"
    refute mix_exs =~ ":tailwind"
  end

  test "the prod_image_api component and its derived plugin both exclude .env" do
    # .dockerignore governs what is SENT TO THE DAEMON, not merely what lands
    # in the image, so a project generated with this plugin would otherwise
    # transmit a local .env (GITHUB_TOKEN, HEX_API_KEY) on every build. The
    # raw component is asserted alongside the derived output because it is the
    # source `mix capstone.plugin.derive` reads: with only the derived file
    # pinned, the next re-derive silently overwrites it back out again, which
    # is exactly how this regressed.
    for file <- [
          "priv/meta/prod_image_api_component/.dockerignore",
          "priv/meta/meta_prod_image_api/files/.dockerignore.eex"
        ] do
      contents = File.read!(file)

      assert contents =~ ~r/^\.env$/m, "#{file} does not exclude .env"
      assert contents =~ ~r/^\.env\.\*$/m, "#{file} does not exclude .env.*"
      assert contents =~ ~r/^!\/\.env\.sample$/m, "#{file} does not re-include .env.sample"
    end
  end

  test "priv/baselines.exs is readable by Capstone.Source.decode!/2" do
    # Pins the task ordering so Baseline can never regress to Code.eval_file/1.
    assert is_map(Capstone.Source.decode!(File.read!("priv/baselines.exs"), "priv/baselines.exs"))
  end

  @tag :toolchain
  test "the installed phx_new version equals the recorded generator_version" do
    # Asserted FIRST, so a phx_new bump gives a one-line message instead of a
    # 45-file hash diff.
    # Selected by the presence of `argv:`, not by name: `web` no longer drives
    # a generator, and a test that iterated every entry would ask a composed
    # baseline for a generator version it does not have.
    %{api: api} = Baseline.read!("priv/baselines.exs")
    {out, 0} = System.cmd("mix", ["phx.new", "-v"])
    assert out =~ api.generator_version
  end

  @tag :toolchain
  test "the api baseline matches fresh phx.new output once both sides are normalised" do
    # Driven from the RECORDED argv, which is what makes `argv:` load-bearing
    # rather than decorative. --no-html --no-assets is the whole point of this
    # baseline: it is the tree the web layer is composed ON TOP of, rather than
    # dismantled out of.
    %{api: api} = Baseline.read!("priv/baselines.exs")
    dir = Path.join(System.tmp_dir!(), "apibase-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    File.mkdir_p!(dir)

    {_out, 0} = System.cmd("mix", ["phx.new" | api.argv], cd: dir)

    assert_same_tree(Baseline.tree(api.path), Baseline.tree(Path.join(dir, hd(api.argv))))
  end

  test "a derived entry carries no generator provenance" do
    # argv:, generator: and generator_version: describe an invocation that no
    # longer happens for a plugin-derived entry.
    %{cache: cache} = Baseline.read!("priv/baselines.exs")

    refute Map.has_key?(cache, :argv)
    refute Map.has_key?(cache, :generator)
    assert cache.derived_from == :api
  end

  test "composing :web from :api plus :web_layer reproduces the checked-in baseline_web" do
    web = Map.fetch!(Baseline.read!("priv/baselines.exs"), :web)
    before = Baseline.tree(web.path)

    capture_io(fn -> Compose.run(["web"]) end)

    assert_same_tree(Baseline.tree(web.path), before)
  end

  defp assert_same_tree(expected, actual) do
    # Never `assert expected == actual` — that dumps two multi-kilobyte maps
    # and names nothing.
    assert Enum.sort(Map.keys(expected)) == Enum.sort(Map.keys(actual))
    differing = for {path, hash} <- expected, actual[path] != hash, do: path
    assert differing == []
  end
end
