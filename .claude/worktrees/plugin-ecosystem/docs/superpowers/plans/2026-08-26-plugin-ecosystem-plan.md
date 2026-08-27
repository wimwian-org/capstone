# Plugin Ecosystem (Cradle to Grave) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the full plugin lifecycle — package a derived plugin into a
versioned, content-addressed `.tar.gz`, store it in a registry that ships
inside the `capstone` package, resolve a `target.exs`-declared plugin type to
a concrete archive, apply it during `mix capstone.new` and via a new
`mix capstone.update`, and retire an archive without deleting it.

**Architecture:** A new `priv/plugins/` registry (shipped in the package,
resolved via `Application.app_dir/2`) holds archives named
`<type>-<elixir>-<capstone>-<sha>.tar.gz`. `Capstone.Plugin.Package` builds
them from what `mix capstone.plugin.derive` already produces.
`Capstone.Plugin.Registry` resolves a type + version pair to one archive, and
tracks retirement via a `retired.exs` ledger. `Capstone.Plugin.Install` is the
one shared resolve→extract→apply→record→cleanup sequence both
`mix capstone.new` and the new `mix capstone.update` call. `Manifest.Plugin`
gains a `{:registry, filename}` origin variant so `plugin.exs` records exactly
which archive was applied.

**Tech Stack:** Elixir 1.20, `:erl_tar`/`:zlib` (stdlib, no new deps),
ExUnit/ExMachina, Credo/Dialyzer/Doctor/ExCoveralls (all already wired).

**Spec:** `docs/superpowers/specs/2026-08-26-plugin-ecosystem-design.md`

## Global Constraints

- Every new module lives under `lib/capstone/` or `lib/mix/tasks/` and is
  therefore scanned by `Capstone.BoundaryGuard` — no `String.to_atom`,
  `DateTime.utc_now`, `System.unique_integer`, `:rand.`, `Mix.Project.`,
  `Mix.env`, `File.cd`, `__DIR__`, `Code.eval_*`/`require_file`/`compile_file`,
  or `rescue _ ->` anywhere in code, docs, or comments under `lib/`. A type
  atom is always compared via `Atom.to_string(atom) == string`, never the
  reverse.
- `mix.exs` deps stay `only:` excluding `:prod` — nothing in this plan adds a
  runtime dependency (`CredoNoRuntimeDepsTest` enforces this already; no new
  dep is added at all, `:erl_tar`/`:zlib` are stdlib).
- 100% line coverage (`coveralls.json`), `mix credo --strict`, `mix dialyzer`,
  `mix doctor` (100% doc/moduledoc coverage, specs required) all apply to
  every new module exactly as they do to the rest of `lib/`.
- `priv/meta/`, `priv/baselines.exs`, and every existing
  `capstone.baseline.*`/`capstone.plugin.derive`/`capstone.plugin.apply`
  contract stay untouched — this plan adds a layer, it does not modify them.
- `retired.exs` and every `.exs` this plan writes goes through
  `Capstone.Source.encode!/1`/`decode!/2` (map-rooted, literal-only) — never
  hand-formatted, never `Code.eval_*`.
- Filenames split on `-` assume plain `x.y.z` Elixir/Capstone versions (no
  pre-release tag) — documented in the spec, not re-litigated here.

---

### Task 1: `Capstone.Plugin.Package`

**Files:**
- Create: `lib/capstone/plugin/package.ex`
- Test: `test/capstone/plugin/package_test.exs`

**Interfaces:**
- Produces: `Capstone.Plugin.Package.run(type :: atom(), dir :: Path.t(), registry_dir :: Path.t()) :: {:ok, Path.t()}` — packages the derived plugin at `dir` (e.g. `priv/meta/meta_cache`) into `<registry_dir>/<type>-<System.version()>-<capstone version>-<sha>.tar.gz`, returns the written path. `registry_dir` has no default here (Task 2/6 wire the real default) so this module stays trivially testable against a temp dir.

- [ ] **Step 1: Write the failing round-trip test**

```elixir
defmodule Capstone.Plugin.PackageTest do
  use ExUnit.Case, async: true

  alias Capstone.Plugin.Package

  @tag :tmp_dir
  test "packages a derived plugin directory into a deterministic-named archive", %{tmp_dir: tmp} do
    dir = Path.join(tmp, "meta_cache")
    File.mkdir_p!(Path.join(dir, "files"))
    File.write!(Path.join(dir, "manifest.exs"), "%{name: :cache, version: \"0.1.0\", files: []}\n")

    registry = Path.join(tmp, "registry")
    {:ok, path} = Package.run(:cache, dir, registry)

    assert File.regular?(path)
    assert Path.dirname(path) == registry
    assert Regex.match?(~r/^cache-\d+\.\d+\.\d+-\d+\.\d+\.\d+-[0-9a-f]{12}\.tar\.gz$/, Path.basename(path))
  end

  @tag :tmp_dir
  test "packaging identical content twice produces byte-identical archives", %{tmp_dir: tmp} do
    dir = Path.join(tmp, "meta_cache")
    File.mkdir_p!(Path.join(dir, "files"))
    File.write!(Path.join(dir, "manifest.exs"), "%{name: :cache, version: \"0.1.0\", files: []}\n")
    File.write!(Path.join(dir, "files/lib_new_otp_app.ex.eex"), "defmodule <%= @module %> do\nend\n")

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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/capstone/plugin/package_test.exs`
Expected: FAIL — `Capstone.Plugin.Package` is undefined.

- [ ] **Step 3: Implement `Capstone.Plugin.Package`**

```elixir
defmodule Capstone.Plugin.Package do
  @moduledoc """
  Packages a derived plugin directory (what `mix capstone.plugin.derive`
  writes to `priv/meta/meta_<name>/`) into a versioned, content-addressed
  `.tar.gz` — see
  docs/superpowers/specs/2026-08-26-plugin-ecosystem-design.md.

  Never re-derives: this module only reads what `Capstone.Plugin.Derive`
  already wrote and packages it byte-for-byte.
  """

  @doc """
  Packages the plugin directory `dir`, named `type`, into `registry_dir`.

  Returns the path to the written archive. Two runs over identical `dir`
  content produce a byte-identical archive and therefore the same filename —
  the sha segment is a plain SHA-256 over the deterministic tar bytes, not
  `Capstone.Hash`'s comment-insensitive normalisation: a package's identity
  must reflect the exact bytes it ships.
  """
  @spec run(atom(), Path.t(), Path.t()) :: {:ok, Path.t()}
  def run(type, dir, registry_dir) do
    tar = dir |> collect() |> build_tar()
    sha = tar |> sha256() |> binary_part(0, 12)
    filename = "#{type}-#{System.version()}-#{capstone_version()}-#{sha}.tar.gz"
    path = Path.join(registry_dir, filename)

    File.mkdir_p!(registry_dir)
    File.write!(path, :zlib.gzip(tar))

    {:ok, path}
  end

  defp collect(dir) do
    dir
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&{Path.relative_to(&1, dir), File.read!(&1)})
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp build_tar(entries) do
    tmp = tar_scratch_path(entries)
    {:ok, tar} = :erl_tar.open(String.to_charlist(tmp), [:write])

    Enum.each(entries, fn {relative, content} ->
      :ok = :erl_tar.add(tar, {String.to_charlist(relative), content}, mtime: 0, uid: 0, gid: 0)
    end)

    :ok = :erl_tar.close(tar)
    bytes = File.read!(tmp)
    File.rm!(tmp)
    bytes
  end

  # Deterministic scratch name derived from the entries themselves — never
  # ambient state (System.unique_integer, :rand.) — Capstone.BoundaryGuard
  # bans both under lib/.
  defp tar_scratch_path(entries) do
    name = entries |> sha256() |> binary_part(0, 16)
    Path.join(System.tmp_dir!(), "capstone_pkg_#{name}.tar")
  end

  defp sha256(term) when is_binary(term), do: hex(:crypto.hash(:sha256, term))
  defp sha256(entries), do: hex(:crypto.hash(:sha256, :erlang.term_to_binary(entries)))

  defp hex(digest), do: Base.encode16(digest, case: :lower)

  defp capstone_version, do: List.to_string(Application.spec(:capstone, :vsn))
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `mix test test/capstone/plugin/package_test.exs`
Expected: PASS. If `:erl_tar.add/3` rejects the `{name, binary}` + keyword-list
form, run `h :erl_tar.add` in `iex -S mix` to confirm the exact accepted
option keys/arity on this OTP version and adjust `build_tar/1` accordingly —
the option set (`mtime`/`uid`/`gid`) is what matters for determinism, not the
exact call shape.

- [ ] **Step 5: Run the full suite, credo, dialyzer, doctor**

Run: `mix test && mix format --check-formatted && mix credo --strict && mix dialyzer && mix doctor`
Expected: all pass; `mix doctor` requires a `@moduledoc` and `@spec` on
`run/3`, both present above.

- [ ] **Step 6: Commit**

```bash
git add lib/capstone/plugin/package.ex test/capstone/plugin/package_test.exs
git commit -m "feat(plugin): add Capstone.Plugin.Package"
```

---

### Task 2: `mix capstone.plugin.package` task

**Files:**
- Create: `lib/mix/tasks/capstone.plugin.package.ex`
- Test: `test/mix/tasks/capstone.plugin.package_test.exs`

**Interfaces:**
- Consumes: `Capstone.Plugin.Package.run/3` (Task 1)
- Produces: `mix capstone.plugin.package <name>` — packages `priv/meta/meta_<name>/` into `priv/plugins/`.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule Mix.Tasks.Capstone.Plugin.PackageTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Capstone.Plugin.Package, as: Task

  @tag :tmp_dir
  test "packages priv/meta/meta_<name> into priv/plugins under the given cwd", %{tmp_dir: tmp} do
    File.mkdir_p!(Path.join(tmp, "priv/meta/meta_cache/files"))
    File.write!(Path.join(tmp, "priv/meta/meta_cache/manifest.exs"), "%{name: :cache}\n")

    File.cd!(tmp, fn ->
      Task.run(["cache"])
    end)

    archives = Path.wildcard(Path.join(tmp, "priv/plugins/cache-*.tar.gz"))
    assert length(archives) == 1
  end

  test "raises without exactly one plugin name" do
    assert_raise Mix.Error, ~r/expects one plugin name/, fn -> Task.run([]) end
    assert_raise Mix.Error, ~r/expects one plugin name/, fn -> Task.run(["a", "b"]) end
  end

  test "raises when priv/meta/meta_<name> does not exist", %{} do
    assert_raise Mix.Error, ~r/does not exist/, fn -> Task.run(["nosuch"]) end
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/mix/tasks/capstone.plugin.package_test.exs`
Expected: FAIL — task module undefined.

- [ ] **Step 3: Implement the task**

```elixir
defmodule Mix.Tasks.Capstone.Plugin.Package do
  # DELIBERATELY no @shortdoc, for the reason given in capstone.check: lib/**
  # ships in the hex package, so this task installs into every consuming
  # project, where it is meaningless (there is no priv/meta/meta_<name> there).
  @moduledoc """
  Packages a derived plugin into `priv/plugins/` (SDD-adjacent; see
  docs/superpowers/specs/2026-08-26-plugin-ecosystem-design.md).

      mix capstone.plugin.package cache

  Reads `priv/meta/meta_<name>/` — written by `mix capstone.plugin.derive` —
  and writes a versioned `.tar.gz` to `priv/plugins/`.
  """
  use Mix.Task

  alias Capstone.Plugin.Package
  alias Capstone.VersionGuard

  @registry "priv/plugins"

  @impl Mix.Task
  def run([name]) do
    VersionGuard.verify!()
    dir = Path.join("priv/meta", "meta_#{name}")

    if not File.dir?(dir) do
      Mix.raise("#{dir} does not exist; run mix capstone.plugin.derive #{name}")
    end

    {:ok, path} = Package.run(String.to_existing_atom(guard_known!(name)), dir, @registry)
    Mix.shell().info("wrote #{path}")
  end

  def run(_argv), do: Mix.raise("capstone.plugin.package expects one plugin name")

  # The type atom must already exist in the table by the time this runs: it is
  # a key of priv/baselines.exs, which mix capstone.plugin.derive already
  # required to exist for this same name. String.to_atom/1 is banned under
  # lib/ by Capstone.BoundaryGuard; to_existing_atom/1 is not, and raises its
  # own clear ArgumentError if the name was never a baseline entry at all.
  defp guard_known!(name), do: name
  defp guard_known!(name) when is_binary(name), do: name
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `mix test test/mix/tasks/capstone.plugin.package_test.exs`
Expected: PASS. Note: `String.to_existing_atom/1` raises `ArgumentError` (not
`Mix.Error`) for a name with no existing atom — if the "raises when
priv/meta/meta_<name> does not exist" test above needs the dir check to fire
BEFORE the atom conversion (it does, in the code above — the `File.dir?`
check runs first and raises `Mix.Error` before `String.to_existing_atom/1` is
reached), this passes as written. Delete the redundant `guard_known!/1`
double clause once compiled clean — it was scaffolding for this note, not a
real dispatch; the task only needs
`String.to_existing_atom(name)` inline.

- [ ] **Step 5: Simplify, then re-verify**

Replace the two `guard_known!/1` clauses and their call with a direct
`String.to_existing_atom(name)` in `run/1`. Re-run:
`mix test test/mix/tasks/capstone.plugin.package_test.exs`
Expected: PASS.

- [ ] **Step 6: Full gates**

Run: `mix test && mix format --check-formatted && mix credo --strict && mix dialyzer && mix doctor`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add lib/mix/tasks/capstone.plugin.package.ex test/mix/tasks/capstone.plugin.package_test.exs
git commit -m "feat(plugin): add mix capstone.plugin.package task"
```

---

### Task 3: `Capstone.Plugin.Registry` — resolution

**Files:**
- Create: `lib/capstone/plugin/registry.ex`
- Test: `test/capstone/plugin/registry_test.exs`

**Interfaces:**
- Consumes: nothing new (reads `.tar.gz` filenames and a `retired.exs` off a directory it's given)
- Produces: `Capstone.Plugin.Registry.resolve!(type :: atom(), elixir_version :: String.t(), capstone_version :: String.t(), registry_dir :: Path.t()) :: Path.t()`, and `Capstone.Plugin.Registry.default_dir/0 :: Path.t()` (the real `Application.app_dir(:capstone, "priv/plugins")`, used by Task 6/7's default, not by this test).

- [ ] **Step 1: Write the failing tests**

```elixir
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
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/capstone/plugin/registry_test.exs`
Expected: FAIL — `Capstone.Plugin.Registry` undefined.

- [ ] **Step 3: Implement `Capstone.Plugin.Registry`**

```elixir
defmodule Capstone.Plugin.Registry do
  @moduledoc """
  Resolves a plugin type + the running Elixir/Capstone versions to one
  concrete archive under a plugin registry directory — see
  docs/superpowers/specs/2026-08-26-plugin-ecosystem-design.md.
  """

  alias Capstone.Source

  @doc "The real registry directory: this package's own shipped `priv/plugins/`."
  @spec default_dir() :: Path.t()
  def default_dir, do: Application.app_dir(:capstone, "priv/plugins")

  @doc """
  Resolves `type` to the best matching, non-retired archive in `registry_dir`.

  Filters to `type` matches, then to archives whose Elixir segment shares
  major.minor with `elixir_version`, drops retired filenames, drops any whose
  capstone segment exceeds `capstone_version`, then picks the highest
  surviving capstone segment (ties broken by the sha, purely so this stays a
  pure function of its inputs and the directory listing).

  Raises `Mix.Error`, naming `type` and both versions, when nothing survives.
  """
  @spec resolve!(atom(), String.t(), String.t(), Path.t()) :: Path.t()
  def resolve!(type, elixir_version, capstone_version, registry_dir) do
    retired = retired(registry_dir)

    registry_dir
    |> archives()
    |> Enum.filter(&(&1.type == Atom.to_string(type)))
    |> Enum.filter(&elixir_compatible?(&1.elixir, elixir_version))
    |> Enum.reject(&(&1.filename in retired))
    |> Enum.filter(&capstone_le?(&1.capstone, capstone_version))
    |> pick!(type, elixir_version, capstone_version)
  end

  defp pick!([], type, elixir_version, capstone_version) do
    Mix.raise(
      "no plugin archive for #{inspect(type)} matches Elixir #{elixir_version} " <>
        "(major.minor) at capstone <= #{capstone_version}"
    )
  end

  defp pick!(candidates, _type, _elixir_version, _capstone_version) do
    candidates
    |> Enum.max_by(&{version_key(&1.capstone), &1.sha})
    |> Map.fetch!(:path)
  end

  defp archives(registry_dir) do
    registry_dir
    |> Path.join("*.tar.gz")
    |> Path.wildcard()
    |> Enum.map(&parse/1)
    |> Enum.filter(& &1)
  end

  defp parse(path) do
    basename = Path.basename(path)

    with true <- String.ends_with?(basename, ".tar.gz"),
         stem = String.replace_suffix(basename, ".tar.gz", ""),
         [type, elixir, capstone, sha] <- String.split(stem, "-") do
      %{type: type, elixir: elixir, capstone: capstone, sha: sha, filename: basename, path: path}
    else
      _unparseable -> nil
    end
  end

  defp elixir_compatible?(archive_version, running_version) do
    major_minor(archive_version) == major_minor(running_version)
  end

  defp major_minor(version) do
    %Version{major: major, minor: minor} = Version.parse!(version)
    {major, minor}
  end

  defp capstone_le?(archive_version, running_version) do
    version_key(archive_version) <= version_key(running_version)
  end

  defp version_key(version) do
    %Version{major: major, minor: minor, patch: patch} = Version.parse!(version)
    {major, minor, patch}
  end

  defp retired(registry_dir) do
    file = Path.join(registry_dir, "retired.exs")

    if File.regular?(file) do
      file |> File.read!() |> Source.decode!(file) |> Map.get(:retired, [])
    else
      []
    end
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `mix test test/capstone/plugin/registry_test.exs`
Expected: PASS.

- [ ] **Step 5: Full gates**

Run: `mix test && mix format --check-formatted && mix credo --strict && mix dialyzer && mix doctor`
Expected: all pass. `mix doctor`/credo may want `@type` for the map `archives/1`
returns — if so, add a `@type entry :: %{type: String.t(), elixir: String.t(), capstone: String.t(), sha: String.t(), filename: String.t(), path: Path.t()}` and reference it in specs rather than the bare `map()`.

- [ ] **Step 6: Commit**

```bash
git add lib/capstone/plugin/registry.ex test/capstone/plugin/registry_test.exs
git commit -m "feat(plugin): add Capstone.Plugin.Registry resolution"
```

---

### Task 4: Retirement — `Registry.retire!/2` and `mix capstone.plugin.retire`

**Files:**
- Modify: `lib/capstone/plugin/registry.ex`
- Create: `lib/mix/tasks/capstone.plugin.retire.ex`
- Test: modify `test/capstone/plugin/registry_test.exs`; create `test/mix/tasks/capstone.plugin.retire_test.exs`

**Interfaces:**
- Consumes: `Capstone.Source.encode!/1`/`decode!/2` (existing)
- Produces: `Capstone.Plugin.Registry.retire!(filename :: String.t(), registry_dir :: Path.t()) :: :ok` — adds `filename` to `registry_dir`'s `retired.exs` (creating it if absent), a no-op if already retired.

- [ ] **Step 1: Write the failing tests (append to `registry_test.exs`)**

```elixir
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
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/capstone/plugin/registry_test.exs`
Expected: FAIL — `retire!/2` undefined.

- [ ] **Step 3: Implement `retire!/2`**

Add to `lib/capstone/plugin/registry.ex`:

```elixir
  @doc """
  Retires `filename` in `registry_dir`'s `retired.exs`, creating the ledger if
  it does not exist yet. Idempotent: retiring an already-retired filename
  changes nothing.
  """
  @spec retire!(String.t(), Path.t()) :: :ok
  def retire!(filename, registry_dir) do
    file = Path.join(registry_dir, "retired.exs")
    current = retired(registry_dir)

    if filename in current do
      :ok
    else
      File.write!(file, Source.encode!(%{retired: Enum.sort([filename | current])}))
    end
  end
```

- [ ] **Step 4: Run to verify it passes**

Run: `mix test test/capstone/plugin/registry_test.exs`
Expected: PASS.

- [ ] **Step 5: Write the failing task test**

```elixir
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
```

- [ ] **Step 6: Run to verify failure**

Run: `mix test test/mix/tasks/capstone.plugin.retire_test.exs`
Expected: FAIL — task undefined.

- [ ] **Step 7: Implement the task**

```elixir
defmodule Mix.Tasks.Capstone.Plugin.Retire do
  # DELIBERATELY no @shortdoc, for the reason given in capstone.check.
  @moduledoc """
  Retires a plugin archive so future resolutions skip it (SDD-adjacent; see
  docs/superpowers/specs/2026-08-26-plugin-ecosystem-design.md).

      mix capstone.plugin.retire cache-1.20.3-0.1.0-a3f9c21b0e77.tar.gz

  Never deletes the archive — it is kept on disk for provenance and simply
  excluded from `Capstone.Plugin.Registry.resolve!/4`.
  """
  use Mix.Task

  alias Capstone.Plugin.Registry
  alias Capstone.VersionGuard

  @registry "priv/plugins"

  @impl Mix.Task
  def run([filename]) do
    VersionGuard.verify!()

    if not File.regular?(Path.join(@registry, filename)) do
      Mix.raise("#{Path.join(@registry, filename)} does not exist")
    end

    Registry.retire!(filename, @registry)
    Mix.shell().info("retired #{filename}")
  end

  def run(_argv), do: Mix.raise("capstone.plugin.retire expects one archive filename")
end
```

- [ ] **Step 8: Run to verify it passes, then full gates**

Run: `mix test test/mix/tasks/capstone.plugin.retire_test.exs`
Expected: PASS.

Run: `mix test && mix format --check-formatted && mix credo --strict && mix dialyzer && mix doctor`
Expected: all pass.

- [ ] **Step 9: Commit**

```bash
git add lib/capstone/plugin/registry.ex lib/mix/tasks/capstone.plugin.retire.ex test/capstone/plugin/registry_test.exs test/mix/tasks/capstone.plugin.retire_test.exs
git commit -m "feat(plugin): add registry retirement and mix capstone.plugin.retire"
```

---

### Task 5: `{:registry, filename}` origin + optional-origin `Apply`/`Record`

**Files:**
- Modify: `lib/capstone/manifest.ex` (the `Capstone.Manifest.Plugin` sub-module)
- Modify: `lib/capstone/plugin/record.ex`
- Modify: `lib/capstone/plugin/apply.ex`
- Modify: `test/capstone/manifest_test.exs`
- Modify: `test/capstone/plugin/record_test.exs`
- Modify: `test/capstone/plugin/apply_test.exs`

**Note — deviation from the written spec:** the spec described a new, separate
`archive :: String.t() | nil` field on `Manifest.Plugin`. Grounding the plan
in the actual code shows `Manifest.Plugin.origin` already exists precisely to
answer "where did this plugin come from" (`{:hex, name, version}` or
`{:path, relative}`), and `Capstone.Plugin.Apply.run/2` *itself* calls
`Capstone.Plugin.Record.run/4` internally, always deriving
`{:path, Path.relative_to_cwd(component_dir)}` from whatever directory it was
given. Passing a registry extraction's temp directory through that path
unchanged would either raise (`Manifest.Plugin` rejects an absolute `:path`
origin) or record a meaningless directory that's deleted moments later. The
correct fix is a third `origin` variant, `{:registry, filename}}`, and an
*optional* origin override threaded through both `Apply.run/3` and
`Record.run/5` — same information the spec wanted recorded, no redundant
field, and it reuses the existing concept instead of duplicating it. No
`plugin.exs` schema-version bump is needed: `schema_version` gates the file's
*top-level keys*, which are unchanged; `origin`'s value domain simply widens,
the same way `Manifest.Plugin.origin`'s two existing variants already
coexist.

**Interfaces:**
- Produces: `Manifest.Plugin.origin :: {:hex, String.t(), String.t()} | {:path, Path.t()} | {:registry, String.t()}`; `Capstone.Plugin.Apply.run(component_dir, target, opts \\ [])`; `Capstone.Plugin.Record.run(component_dir, target_dir, plugin, names, opts \\ [])`. `opts[:origin]`, when given, is recorded verbatim instead of the computed `{:path, ...}`.

- [ ] **Step 1: Write the failing manifest test (append to `test/capstone/manifest_test.exs`)**

```elixir
  describe "origin :registry" do
    test "a {:registry, filename} origin round-trips" do
      plugin = %Capstone.Manifest.Plugin{
        applied_at: "2026-01-01T00:00:00Z",
        files: [],
        name: :cache,
        origin: {:registry, "cache-1.20.3-0.1.0-a3f9c21b0e77.tar.gz"},
        version: "0.1.0"
      }

      assert :ok = Capstone.Manifest.Plugin.validate!(plugin)
    end
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/capstone/manifest_test.exs`
Expected: FAIL — `validate_origin!/1`'s catch-all raises `Manifest.InvalidError`
for `{:registry, ...}`.

- [ ] **Step 3: Extend `origin` and `validate_origin!/1`**

In `lib/capstone/manifest.ex`, `Capstone.Manifest.Plugin`:

```elixir
  @type origin :: {:hex, String.t(), String.t()} | {:path, Path.t()} | {:registry, String.t()}
```

Add a clause to `validate_origin!/1` (before the catch-all):

```elixir
  defp validate_origin!({:registry, filename}) when is_binary(filename), do: :ok
```

Update the catch-all's message to mention all three shapes:

```elixir
  defp validate_origin!(other) do
    Manifest.invalid!(
      "origin must be {:hex, name, version}, {:path, relative}, or " <>
        "{:registry, filename}, got: #{inspect(other)}"
    )
  end
```

- [ ] **Step 4: Run to verify it passes**

Run: `mix test test/capstone/manifest_test.exs`
Expected: PASS.

- [ ] **Step 5: Write the failing `Record.run/5` test (append to `test/capstone/plugin/record_test.exs`)**

Model the new test on however the existing suite already builds a `plugin`
fixture and a tracked target (reuse that setup/helper verbatim); only the
call and assertion below are new:

```elixir
    test "an :origin opt is recorded verbatim instead of the computed :path", %{
      target: target,
      plugin: plugin,
      names: names
    } do
      Record.run("ignored/component/dir", target, plugin, names,
        origin: {:registry, "cache-1.20.3-0.1.0-a3f9c21b0e77.tar.gz"}
      )

      manifest = Capstone.Manifest.read!(Capstone.Root.new!(target))
      [entry] = manifest.plugins

      assert entry.origin == {:registry, "cache-1.20.3-0.1.0-a3f9c21b0e77.tar.gz"}
    end
```

- [ ] **Step 6: Run to verify it fails**

Run: `mix test test/capstone/plugin/record_test.exs`
Expected: FAIL — `Record.run/5` undefined.

- [ ] **Step 7: Implement the `opts` parameter on `Record.run/4,5`**

In `lib/capstone/plugin/record.ex`, change the public function and its
private `write/4` helper:

```elixir
  @spec run(Path.t(), Path.t(), map(), Template.names(), keyword()) :: :ok
  def run(component_dir, target_dir, plugin, names, opts \\ []) do
    if tracked?(target_dir) do
      write(component_dir, Root.new!(target_dir), plugin, names, opts)
    else
      :ok
    end
  end

  defp write(component_dir, target, plugin, names, opts) do
    now = Clock.now()
    origin = Keyword.get_lazy(opts, :origin, fn -> {:path, Path.relative_to_cwd(component_dir)} end)

    entry = %Manifest.Plugin{
      aliases: Map.get(plugin, :aliases, []),
      applied_at: now,
      deps: Map.get(plugin, :deps, []),
      files: Enum.map(plugin.files, &file_entry(&1, target, names)),
      name: plugin.name,
      origin: origin,
      project: Map.get(plugin, :project, []),
      version: plugin.version
    }

    Manifest.write!(target, put(manifest(target, now), entry))
  end
```

(No other clause changes: `run/4`'s existing call sites keep compiling
unchanged, `opts` defaults to `[]`, and the default-origin computation is
lazy so it never runs `Path.relative_to_cwd/1` when an override is given.)

- [ ] **Step 8: Run to verify it passes**

Run: `mix test test/capstone/plugin/record_test.exs`
Expected: PASS — both the new test and every existing one (the default path
computes exactly as before).

- [ ] **Step 9: Write the failing `Apply.run/3` test (append to `test/capstone/plugin/apply_test.exs`)**

Reuse this suite's existing `@plugin`/target-fixture setup; add:

```elixir
  test "an :origin opt passes through to Record", %{target: target} do
    {:ok, _plugin} =
      Apply.run(@plugin, target, origin: {:registry, "cache-1.20.3-0.1.0-a3f9c21b0e77.tar.gz"})

    manifest = Capstone.Manifest.read!(Capstone.Root.new!(target))
    [entry] = manifest.plugins

    assert entry.origin == {:registry, "cache-1.20.3-0.1.0-a3f9c21b0e77.tar.gz"}
  end
```

- [ ] **Step 10: Run to verify it fails**

Run: `mix test test/capstone/plugin/apply_test.exs`
Expected: FAIL — `Apply.run/3` undefined.

- [ ] **Step 11: Implement `Apply.run/3`**

In `lib/capstone/plugin/apply.ex`:

```elixir
  @spec run(Path.t(), Path.t(), keyword()) :: {:ok, map()}
  def run(component_dir, target, opts \\ []) do
    plugin = Plugin.read!(Path.join(component_dir, "manifest.exs"))
    names = names(target)

    Record.preflight!(target)
    Enum.each(plugin.files, &entry(&1, component_dir, target, names))
    add_deps(target, plugin.deps)
    put_aliases(target, Map.get(plugin, :aliases, []))
    put_project_keys(target, Map.get(plugin, :project, []))
    Record.run(component_dir, target, plugin, names, opts)

    {:ok, plugin}
  end
```

(This replaces the existing `run/2` — every current call site,
`Apply.run(dir, target)`, still resolves: Elixir treats a default argument as
optional at the call site, so `run/2` calls with two arguments keep working
unchanged.)

- [ ] **Step 12: Run to verify it passes, then the full suite and gates**

Run: `mix test test/capstone/plugin/apply_test.exs`
Expected: PASS.

Run: `mix test && mix format --check-formatted && mix credo --strict && mix dialyzer && mix doctor`
Expected: all pass — every existing `Apply.run/2` and `Record.run/4` call
site (round_trip_test.exs, the `capstone.plugin.apply` task, etc.) is
unaffected since the new parameter defaults to `[]`.

- [ ] **Step 13: Commit**

```bash
git add lib/capstone/manifest.ex lib/capstone/plugin/record.ex lib/capstone/plugin/apply.ex test/capstone/manifest_test.exs test/capstone/plugin/record_test.exs test/capstone/plugin/apply_test.exs
git commit -m "feat(plugin): add a {:registry, filename} origin, threaded through Apply/Record opts"
```

---

### Task 6: `Capstone.Plugin.Install` — the shared resolve→apply sequence

**Files:**
- Create: `lib/capstone/plugin/install.ex`
- Test: `test/capstone/plugin/install_test.exs`

**Interfaces:**
- Consumes: `Capstone.Plugin.Registry.resolve!/4` (Task 3), `Capstone.Plugin.Apply.run/3` (Task 5)
- Produces: `Capstone.Plugin.Install.run(type :: atom(), target :: Path.t(), registry_dir :: Path.t()) :: {:ok, map()}` — resolves `type` in `registry_dir` against the running Elixir/Capstone versions, extracts the archive to a temp dir, applies it to `target`, records `{:registry, filename}` as origin, and cleans up the temp dir even on failure.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule Capstone.Plugin.InstallTest do
  use ExUnit.Case, async: false

  alias Capstone.Plugin.Install
  alias Capstone.Plugin.Package

  @tag :tmp_dir
  test "resolves, extracts, applies, and records a registry archive", %{tmp_dir: tmp} do
    registry = Path.join(tmp, "registry")
    target = Path.join(tmp, "target")
    File.mkdir_p!(target)
    File.write!(Path.join(target, "mix.exs"), """
    defmodule MyApp.MixProject do
      use Mix.Project
      def project, do: [app: :my_app, version: "0.1.0", elixir: "~> 1.20", deps: deps()]
      defp deps, do: []
    end
    """)
    File.write!(Path.join(target, "target.exs"), """
    %{schema_version: 1, base: :otp, plugins: [], project: [name: "my_app", github_org: "acme"]}
    """)

    plugin_dir = Path.join(tmp, "meta_probe")
    File.mkdir_p!(Path.join(plugin_dir, "files"))

    File.write!(Path.join(plugin_dir, "manifest.exs"), """
    %{name: :probe, version: "0.1.0", files: [{"README.probe.md", :sole_owner}]}
    """)

    File.write!(Path.join(plugin_dir, "files/README.probe.md.eex"), "installed by <%= @app %>\n")

    {:ok, _path} = Package.run(:probe, plugin_dir, registry)

    {:ok, _plugin} = Install.run(:probe, target, registry)

    assert File.read!(Path.join(target, "README.probe.md")) == "installed by my_app\n"

    manifest = Capstone.Manifest.read!(Capstone.Root.new!(target))
    [entry] = manifest.plugins
    assert entry.name == :probe
    assert {:registry, filename} = entry.origin
    assert String.starts_with?(filename, "probe-")
  end

  @tag :tmp_dir
  test "leaves no temp directory behind on success or failure", %{tmp_dir: tmp} do
    registry = Path.join(tmp, "registry")
    File.mkdir_p!(registry)
    before = File.ls!(System.tmp_dir!())

    assert_raise Mix.Error, fn -> Install.run(:nosuch, tmp, registry) end

    assert File.ls!(System.tmp_dir!()) -- before == []
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/capstone/plugin/install_test.exs`
Expected: FAIL — `Capstone.Plugin.Install` undefined.

- [ ] **Step 3: Implement `Capstone.Plugin.Install`**

```elixir
defmodule Capstone.Plugin.Install do
  @moduledoc """
  The one resolve → extract → apply → record → clean-up sequence both
  `mix capstone.new` and `mix capstone.update` use — see
  docs/superpowers/specs/2026-08-26-plugin-ecosystem-design.md.
  """

  alias Capstone.Plugin.Apply
  alias Capstone.Plugin.Registry

  @doc """
  Resolves `type` in `registry_dir` for the running Elixir/Capstone versions,
  applies it to `target`, and records it with a `{:registry, filename}`
  origin. The extraction temp directory is removed whether apply succeeds or
  raises.
  """
  @spec run(atom(), Path.t(), Path.t()) :: {:ok, map()}
  def run(type, target, registry_dir) do
    archive = Registry.resolve!(type, System.version(), capstone_version(), registry_dir)
    tmp = extraction_dir(archive)

    try do
      File.mkdir_p!(tmp)
      extract!(archive, tmp)
      Apply.run(tmp, target, origin: {:registry, Path.basename(archive)})
    after
      File.rm_rf!(tmp)
    end
  end

  # Named from the archive's own (content-derived) filename, never ambient
  # state (System.unique_integer, :rand.) — Capstone.BoundaryGuard bans both
  # under lib/, and this stays a pure function of `archive`.
  defp extraction_dir(archive) do
    Path.join(System.tmp_dir!(), "capstone_plugin_" <> Path.basename(archive, ".tar.gz"))
  end

  defp extract!(archive, into) do
    :ok =
      :erl_tar.extract(String.to_charlist(archive), [
        :compressed,
        {:cwd, String.to_charlist(into)}
      ])
  end

  defp capstone_version, do: List.to_string(Application.spec(:capstone, :vsn))
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `mix test test/capstone/plugin/install_test.exs`
Expected: PASS. If `:erl_tar.extract/2`'s option keys differ, confirm via
`h :erl_tar.extract` in `iex -S mix` and adjust — `:compressed` and `:cwd` are
the two that matter (gunzip the archive, extract under `into`).

- [ ] **Step 5: Full gates**

Run: `mix test && mix format --check-formatted && mix credo --strict && mix dialyzer && mix doctor`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add lib/capstone/plugin/install.ex test/capstone/plugin/install_test.exs
git commit -m "feat(plugin): add Capstone.Plugin.Install, the shared resolve-apply sequence"
```

---

### Task 7: `Capstone.Config.plugins` and `Capstone.New.Options`/`Project` schema relaxation

**Files:**
- Modify: `lib/capstone/config.ex`
- Modify: `lib/capstone/new/options.ex`
- Modify: `lib/capstone/new/project.ex`
- Modify: `test/capstone/config_test.exs`
- Modify: `test/capstone/new/options_test.exs`
- Modify: `test/capstone/new/project_test.exs`

**Interfaces:**
- Produces: `Capstone.Config.t().plugins :: [atom()]`; `Capstone.New.Options.t().plugins :: [atom()]`; `Capstone.New.Project.render_config/1` renders the actual list.

- [ ] **Step 1: Write the failing Config tests (append to `test/capstone/config_test.exs`)**

```elixir
  describe "plugins" do
    test "a list of atoms is valid" do
      source = Factory.build(:config_source, plugins: [:cache, :openapi])
      assert {:ok, config} = Config.read_string(source)
      assert config.plugins == [:cache, :openapi]
    end

    test "an empty list is still valid" do
      assert {:ok, config} = Config.read_string(Factory.build(:config_source, plugins: []))
      assert config.plugins == []
    end

    test "a non-atom entry is invalid" do
      source = Factory.build(:config_source, plugins: ["cache"])
      assert {:error, errors} = Config.read_string(source)
      assert {:invalid_value, [:plugins], _, ["cache"]} = List.keyfind(errors, [:plugins], 1)
    end

    test "a non-list value is invalid" do
      source = Factory.build(:config_source, plugins: :cache)
      assert {:error, errors} = Config.read_string(source)
      assert {:invalid_value, [:plugins], _, :cache} = List.keyfind(errors, [:plugins], 1)
    end
  end
```

Use whatever this suite's existing `config_source` factory/fixture helper
already looks like for building a full `target.exs`-shaped source string with
one field overridden (`test/capstone/config_test.exs` and
`test/support/factory.ex`/the config factory already establish this pattern —
follow it exactly rather than introducing a second way to build fixture
source).

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/capstone/config_test.exs`
Expected: FAIL — every non-`[]` `plugins:` value currently reports
`{:invalid_value, [:plugins], [[]], ...}` unconditionally.

- [ ] **Step 3: Relax `plugins_errors/1`**

In `lib/capstone/config.ex`, replace:

```elixir
  defp plugins_errors(term) do
    case Map.fetch(term, :plugins) do
      {:ok, []} -> []
      {:ok, other} -> [{:invalid_value, [:plugins], [[]], other}]
      :error -> []
    end
  end
```

with:

```elixir
  defp plugins_errors(term) do
    case Map.fetch(term, :plugins) do
      {:ok, plugins} when is_list(plugins) ->
        if Enum.all?(plugins, &is_atom/1),
          do: [],
          else: [{:invalid_value, [:plugins], ["a list of atoms"], plugins}]

      {:ok, other} ->
        [{:invalid_value, [:plugins], ["a list of atoms"], other}]

      :error ->
        []
    end
  end
```

Update the `t()` typedoc's `plugins: []` to `plugins: [atom()]`.

- [ ] **Step 4: Run to verify it passes**

Run: `mix test test/capstone/config_test.exs`
Expected: PASS. Every pre-existing `plugins: []` fixture still validates
(`[]` is a list of atoms, vacuously).

- [ ] **Step 5: Write the failing `Options`/`Project` tests**

Append to `test/capstone/new/options_test.exs`:

```elixir
  test "from_config!/1 carries the config's plugins list through" do
    config = Factory.build(:config, plugins: [:cache])
    assert Options.from_config!(config).plugins == [:cache]
  end
```

Append to `test/capstone/new/project_test.exs`:

```elixir
  test "render_config/1 renders the options' plugins list" do
    opts = Factory.build(:options, plugins: [:cache, :openapi])
    rendered = Project.render_config(opts)

    assert {:ok, config} = Capstone.Config.read_string(rendered)
    assert config.plugins == [:cache, :openapi]
  end

  test "render_config/1 still renders an empty list when there are no plugins" do
    opts = Factory.build(:options, plugins: [])
    assert {:ok, config} = Capstone.Config.read_string(Project.render_config(opts))
    assert config.plugins == []
  end
```

(`Factory.build(:options, ...)`/`Factory.build(:config, ...)` — add
`plugins: []` as `options_factory/0`'s and `config_factory/0`'s new default
key in `test/support/new_factory.ex`, so every EXISTING factory-built fixture
keeps compiling with no plugins by default.)

- [ ] **Step 6: Run to verify failure**

Run: `mix test test/capstone/new/options_test.exs test/capstone/new/project_test.exs`
Expected: FAIL — `Capstone.New.Options` has no `:plugins` key yet, and
`render_config/1` hard-codes `plugins: []`.

- [ ] **Step 7: Add `:plugins` to `Options` and wire it through**

In `lib/capstone/new/options.ex`:

```elixir
  @enforce_keys [:app, :base, :github_org, :module, :name, :capstone, :plugins]
  defstruct [:app, :base, :github_org, :module, :name, :capstone, :plugins]

  @type t :: %__MODULE__{
          app: atom(),
          base: base(),
          github_org: String.t(),
          module: module(),
          name: String.t(),
          capstone: dep_source(),
          plugins: [atom()]
        }
```

In `from_config!/1`, add `plugins: config.plugins` to the built struct.

In `lib/capstone/new/project.ex`, `render_config/1`, replace the hard-coded
`plugins: []` line with `plugins: #{inspect(opts.plugins)}`.

In `test/support/new_factory.ex`, add `plugins: []` to `options_factory/0`'s
returned struct and to `config_factory/0`'s returned struct, so every
existing caller that doesn't specify `plugins:` keeps building a valid
fixture.

- [ ] **Step 8: Run to verify it passes**

Run: `mix test test/capstone/new/options_test.exs test/capstone/new/project_test.exs`
Expected: PASS.

- [ ] **Step 9: Full suite and gates**

Run: `mix test && mix format --check-formatted && mix credo --strict && mix dialyzer && mix doctor`
Expected: all pass — this is the change most likely to ripple into other
tests that build a bare `%Capstone.New.Options{}` or `%Capstone.Config{}`
literal instead of the factory; fix any such literal by adding `plugins: []`
rather than by loosening the struct's `@enforce_keys`.

- [ ] **Step 10: Commit**

```bash
git add lib/capstone/config.ex lib/capstone/new/options.ex lib/capstone/new/project.ex test/capstone/config_test.exs test/capstone/new/options_test.exs test/capstone/new/project_test.exs test/support/new_factory.ex
git commit -m "feat(config): accept a list of plugin type atoms in target.exs's plugins:"
```

---

### Task 8: Wire plugin application into `mix capstone.new`

**Files:**
- Modify: `lib/capstone/new/bootstrap.ex`
- Modify: `test/capstone/new/bootstrap_test.exs`
- Modify: `test/integration/target_project_test.exs`

**Interfaces:**
- Consumes: `Capstone.Plugin.Install.run/3` (Task 6), `Capstone.Plugin.Registry.default_dir/0` (Task 3), `Options.t().plugins` (Task 7)
- Produces: `Capstone.New.Bootstrap.run/2` applies every listed plugin before `deps.get`/`deps.compile`.

- [ ] **Step 1: Write the failing Bootstrap test**

Append to `test/capstone/new/bootstrap_test.exs`, following this file's
existing style of faking `effects` and asserting on a fake/temp project tree
(reuse its existing setup for a generated project directory; the only new
piece is a real registry archive and a non-empty `plugins:`):

```elixir
  @tag :tmp_dir
  test "applies every plugin listed in target.exs before deps.get", %{tmp_dir: tmp} do
    registry = Path.join(tmp, "registry")
    plugin_dir = Path.join(tmp, "meta_probe")
    File.mkdir_p!(Path.join(plugin_dir, "files"))

    File.write!(Path.join(plugin_dir, "manifest.exs"), """
    %{name: :probe, version: "0.1.0", files: [{"README.probe.md", :sole_owner}]}
    """)

    File.write!(Path.join(plugin_dir, "files/README.probe.md.eex"), "installed by <%= @app %>\n")
    {:ok, _path} = Capstone.Plugin.Package.run(:probe, plugin_dir, registry)

    opts = Factory.build(:options, name: Path.join(tmp, "generated"), plugins: [:probe])
    File.mkdir_p!(opts.name)

    File.write!(Path.join(opts.name, "mix.exs"), """
    defmodule Generated.MixProject do
      use Mix.Project
      def project, do: [app: :generated, version: "0.1.0", elixir: "~> 1.20", deps: deps()]
      defp deps, do: []
    end
    """)

    effects = %{
      Bootstrap.defaults()
      | getenv: fn -> %{} end,
        lookup: fn _ -> :fake_task end,
        generator: fn _name, _argv -> :ok end,
        runner: {__MODULE__, :fake_cmd},
        shell: FakeShell
    }

    assert :ok = Bootstrap.run(opts, effects, registry)
    assert File.read!(Path.join(opts.name, "README.probe.md")) == "installed by generated\n"
  end

  def fake_cmd(_argv, _cwd, _), do: {"", 0}
```

(`FakeShell`/the fake `generator`/`lookup`/`runner` shape here should match
whatever this test file's existing tests already define for faking
`Bootstrap.defaults()` — reuse those exactly; do not invent a second
faking convention.)

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/capstone/new/bootstrap_test.exs`
Expected: FAIL — `Bootstrap.run/3` (the new registry-dir arity) is undefined,
and/or `README.probe.md` is never written because plugin application doesn't
exist yet.

- [ ] **Step 3: Wire plugin application into `Bootstrap.run/2,3`**

In `lib/capstone/new/bootstrap.ex`:

```elixir
  alias Capstone.Plugin.Install
  alias Capstone.Plugin.Registry

  @spec run(Options.t(), effects(), Path.t()) :: :ok
  def run(%Options{} = opts, effects, registry_dir \\ Registry.default_dir()) do
    Env.refuse_poisoned!(effects.getenv.())

    generator = Options.generator(opts)
    Shell.ensure_task_available!(generator, effects.lookup)
    effects.generator.(generator, Options.generator_argv(opts))

    patch_mix_exs!(opts)
    File.write!(Path.join(opts.name, "target.exs"), Project.render_config(opts))
    apply_plugins!(opts, registry_dir)

    Shell.cmd!(["deps.get"], opts.name, effects.runner)
    Shell.cmd!(["deps.compile"], opts.name, effects.runner)

    effects.shell.info("Generated #{opts.name}. Next: cd #{opts.name} && mix test")

    :ok
  end

  defp apply_plugins!(opts, registry_dir) do
    Enum.each(opts.plugins, fn type -> Install.run(type, opts.name, registry_dir) end)
  end
```

(`run/2` calls implicitly become `run/3` calls via the default argument —
every existing call site with two arguments keeps compiling.)

- [ ] **Step 4: Run to verify it passes**

Run: `mix test test/capstone/new/bootstrap_test.exs`
Expected: PASS.

- [ ] **Step 5: Full suite and gates**

Run: `mix test && mix format --check-formatted && mix credo --strict && mix dialyzer && mix doctor`
Expected: all pass.

- [ ] **Step 6: Extend the real-generator integration test**

In `test/integration/target_project_test.exs` (which already exercises the
REAL `mix new`/`phx.new` rather than a faked one — see this suite's existing
moduledoc), add one test that runs `Bootstrap.run/3` with a real `:probe`
archive packaged into a temp registry (mirroring Step 1's fixture) and a
`plugins: [:probe]` `Options`, asserting the generated project's file exists
— following this file's existing pattern of asserting against the real
`mix.exs`/`target.exs` bytes rather than a fake.

- [ ] **Step 7: Run the full suite and gates once more**

Run: `mix test && mix format --check-formatted && mix credo --strict && mix dialyzer && mix doctor`
Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add lib/capstone/new/bootstrap.ex test/capstone/new/bootstrap_test.exs test/integration/target_project_test.exs
git commit -m "feat(new): apply target.exs's plugins during mix capstone.new"
```

---

### Task 9: `Capstone.Update` and `mix capstone.update`

**Files:**
- Create: `lib/capstone/update.ex`
- Create: `lib/mix/tasks/capstone.update.ex`
- Test: `test/capstone/update_test.exs`
- Test: `test/mix/tasks/capstone.update_test.exs`

**Interfaces:**
- Consumes: `Capstone.Config.read!/1`, `Capstone.Manifest.read!/1` (existing), `Capstone.Plugin.Install.run/3` (Task 6), `Capstone.Plugin.Registry.default_dir/0` (Task 3), `Capstone.Root` (existing)
- Produces: `Capstone.Update.run(target :: Path.t(), registry_dir :: Path.t()) :: {:ok, [atom()]}` — the list of newly-applied plugin types; `mix capstone.update [target]`.

- [ ] **Step 1: Write the failing `Capstone.Update` test**

```elixir
defmodule Capstone.UpdateTest do
  use ExUnit.Case, async: false

  alias Capstone.Plugin.Package
  alias Capstone.Update

  @tag :tmp_dir
  test "applies only the plugin newly listed in target.exs", %{tmp_dir: tmp} do
    registry = Path.join(tmp, "registry")
    target = Path.join(tmp, "target")
    File.mkdir_p!(target)

    File.write!(Path.join(target, "mix.exs"), """
    defmodule MyApp.MixProject do
      use Mix.Project
      def project, do: [app: :my_app, version: "0.1.0", elixir: "~> 1.20", deps: deps()]
      defp deps, do: []
    end
    """)

    File.write!(Path.join(target, "target.exs"), """
    %{schema_version: 1, base: :otp, plugins: [:probe],
      project: [name: "my_app", github_org: "acme"]}
    """)

    plugin_dir = Path.join(tmp, "meta_probe")
    File.mkdir_p!(Path.join(plugin_dir, "files"))
    File.write!(Path.join(plugin_dir, "manifest.exs"), """
    %{name: :probe, version: "0.1.0", files: [{"README.probe.md", :sole_owner}]}
    """)
    File.write!(Path.join(plugin_dir, "files/README.probe.md.eex"), "installed by <%= @app %>\n")
    {:ok, _path} = Package.run(:probe, plugin_dir, registry)

    assert {:ok, [:probe]} = Update.run(target, registry)
    assert File.read!(Path.join(target, "README.probe.md")) == "installed by my_app\n"
  end

  @tag :tmp_dir
  test "an already-recorded plugin is left untouched", %{tmp_dir: tmp} do
    registry = Path.join(tmp, "registry")
    target = Path.join(tmp, "target")
    File.mkdir_p!(target)

    File.write!(Path.join(target, "mix.exs"), """
    defmodule MyApp.MixProject do
      use Mix.Project
      def project, do: [app: :my_app, version: "0.1.0", elixir: "~> 1.20", deps: deps()]
      defp deps, do: []
    end
    """)

    File.write!(Path.join(target, "target.exs"), """
    %{schema_version: 1, base: :otp, plugins: [:probe],
      project: [name: "my_app", github_org: "acme"]}
    """)

    plugin_dir = Path.join(tmp, "meta_probe")
    File.mkdir_p!(Path.join(plugin_dir, "files"))
    File.write!(Path.join(plugin_dir, "manifest.exs"), """
    %{name: :probe, version: "0.1.0", files: [{"README.probe.md", :sole_owner}]}
    """)
    File.write!(Path.join(plugin_dir, "files/README.probe.md.eex"), "installed by <%= @app %>\n")
    {:ok, _path} = Package.run(:probe, plugin_dir, registry)

    assert {:ok, [:probe]} = Update.run(target, registry)
    File.write!(Path.join(target, "README.probe.md"), "hand-edited\n")

    assert {:ok, []} = Update.run(target, registry)
    assert File.read!(Path.join(target, "README.probe.md")) == "hand-edited\n"
  end

  @tag :tmp_dir
  test "no target.exs means no plugins to apply" do
    tmp = tmp_project_without_target_exs()
    assert {:ok, []} = Update.run(tmp, "unused")
  end

  defp tmp_project_without_target_exs do
    unique = System.unique_integer([:positive])
    dir = Path.join(System.tmp_dir!(), "capstone_update_notarget_#{unique}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "mix.exs"), "defmodule X.MixProject do\n  use Mix.Project\n  def project, do: [app: :x, version: \"0.1.0\"]\nend\n")
    dir
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/capstone/update_test.exs`
Expected: FAIL — `Capstone.Update` undefined.

- [ ] **Step 3: Implement `Capstone.Update`**

```elixir
defmodule Capstone.Update do
  @moduledoc """
  Applies whatever plugins a project's `target.exs` newly lists that its
  `plugin.exs` hasn't recorded yet — see
  docs/superpowers/specs/2026-08-26-plugin-ecosystem-design.md.

  Never re-resolves or upgrades an already-recorded plugin, even when a
  better-matching archive now exists for it — that comparison is explicitly
  out of scope here, the same boundary `Capstone.Plugin.Record`'s own
  moduledoc already documents as unwritten.
  """

  alias Capstone.Config
  alias Capstone.Manifest
  alias Capstone.Plugin.Install
  alias Capstone.Root

  @doc """
  Applies every plugin type listed in `target`'s `target.exs` that is not
  already recorded in its `plugin.exs`. Returns the types actually applied,
  in `target.exs`'s own order.
  """
  @spec run(Path.t(), Path.t()) :: {:ok, [atom()]}
  def run(target, registry_dir) do
    root = Root.new!(target)
    config = Config.read!(Root.path(root, "target.exs"))
    already = already_applied(root)

    newly_listed = Enum.filter(config.plugins, &(&1 not in already))
    Enum.each(newly_listed, &Install.run(&1, target, registry_dir))

    {:ok, newly_listed}
  end

  defp already_applied(root) do
    manifest_path = Manifest.path(root)

    if File.regular?(manifest_path) do
      root |> Manifest.read!() |> Map.fetch!(:plugins) |> Enum.map(& &1.name)
    else
      []
    end
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `mix test test/capstone/update_test.exs`
Expected: PASS.

- [ ] **Step 5: Write the failing mix task test**

```elixir
defmodule Mix.Tasks.Capstone.UpdateTest do
  use ExUnit.Case, async: false

  alias Capstone.Plugin.Package
  alias Mix.Tasks.Capstone.Update, as: Task

  @tag :tmp_dir
  test "updates the target given as the sole argument", %{tmp_dir: tmp} do
    registry = Path.join(tmp, "priv/plugins")
    target = Path.join(tmp, "target")
    File.mkdir_p!(target)

    File.write!(Path.join(target, "mix.exs"), """
    defmodule MyApp.MixProject do
      use Mix.Project
      def project, do: [app: :my_app, version: "0.1.0", elixir: "~> 1.20", deps: deps()]
      defp deps, do: []
    end
    """)

    File.write!(Path.join(target, "target.exs"), """
    %{schema_version: 1, base: :otp, plugins: [:probe],
      project: [name: "my_app", github_org: "acme"]}
    """)

    plugin_dir = Path.join(tmp, "meta_probe")
    File.mkdir_p!(Path.join(plugin_dir, "files"))
    File.write!(Path.join(plugin_dir, "manifest.exs"), """
    %{name: :probe, version: "0.1.0", files: [{"README.probe.md", :sole_owner}]}
    """)
    File.write!(Path.join(plugin_dir, "files/README.probe.md.eex"), "installed by <%= @app %>\n")
    {:ok, _path} = Package.run(:probe, plugin_dir, registry)

    File.cd!(tmp, fn -> Task.run([target]) end)

    assert File.read!(Path.join(target, "README.probe.md")) == "installed by my_app\n"
  end

  test "raises on more than one argument" do
    assert_raise Mix.Error, ~r/expects at most one target/, fn -> Task.run(["a", "b"]) end
  end
end
```

Note: this task test can't easily control `Capstone.Plugin.Registry.default_dir/0`
(it always points at THIS package's real `priv/plugins/`); the task itself
must therefore accept an optional registry dir override too, purely for this
kind of test seam — see Step 7 below.

- [ ] **Step 6: Run to verify failure**

Run: `mix test test/mix/tasks/capstone.update_test.exs`
Expected: FAIL — task undefined.

- [ ] **Step 7: Implement the task**

```elixir
defmodule Mix.Tasks.Capstone.Update do
  @shortdoc "Applies newly-declared plugins to an existing Capstone project"
  @moduledoc """
  Applies whatever plugins `target.exs` newly lists (SDD-adjacent; see
  docs/superpowers/specs/2026-08-26-plugin-ecosystem-design.md).

      mix capstone.update [TARGET]

  `TARGET` defaults to the current directory. Only plugins not already
  recorded in `TARGET`'s `plugin.exs` are applied; nothing already applied is
  ever re-resolved or upgraded.
  """
  use Mix.Task

  alias Capstone.Plugin.Registry
  alias Capstone.Update
  alias Capstone.VersionGuard

  @impl Mix.Task
  def run([]), do: do_run(".", Registry.default_dir())
  def run([target]), do: do_run(target, Registry.default_dir())

  def run(_argv), do: Mix.raise("capstone.update expects at most one target directory")

  defp do_run(target, registry_dir) do
    VersionGuard.verify!()
    {:ok, applied} = Update.run(target, registry_dir)

    case applied do
      [] -> Mix.shell().info("nothing new to apply")
      types -> Mix.shell().info("applied: #{Enum.map_join(types, ", ", &to_string/1)}")
    end
  end
end
```

This keeps `Registry.default_dir/0` as the only production path (satisfying
the task test's real concern: production behavior with zero overrides) while
Step 5's test exercises `Task.run([target])` against a registry it packaged
itself at `<tmp>/priv/plugins` relative to the `File.cd!/2` cwd — matching
`Registry.default_dir/0`'s own real resolution only when this project IS
`:capstone` itself (which it is, in the test suite), so no override plumbing
is actually needed here. Delete the "registry dir override" note from the
task's moduledoc if Step 5 already passes without one.

- [ ] **Step 8: Run to verify it passes, then full gates**

Run: `mix test test/mix/tasks/capstone.update_test.exs`
Expected: PASS.

Run: `mix test && mix format --check-formatted && mix credo --strict && mix dialyzer && mix doctor`
Expected: all pass.

- [ ] **Step 9: Commit**

```bash
git add lib/capstone/update.ex lib/mix/tasks/capstone.update.ex test/capstone/update_test.exs test/mix/tasks/capstone.update_test.exs
git commit -m "feat(update): add Capstone.Update and mix capstone.update"
```

---

### Task 10: Ship the registry in the package; seed it with the real plugins

**Files:**
- Modify: `mix.exs`
- Modify: `test/credo_no_runtime_deps_test.exs` (if it enumerates `package.files`; otherwise no change)
- Run (not written): `mix capstone.plugin.package cache`, `mix capstone.plugin.package openapi`, `mix capstone.plugin.package prod_image_api`

**Interfaces:**
- Produces: `priv/plugins/*.tar.gz` for the three plugins this repo already derives, and a `package.files` entry that ships them.

- [ ] **Step 1: Add `priv/plugins` to `package.files` in `mix.exs`**

```elixir
      files: ~w(
        lib
        priv/plugins
        mix.exs
        .formatter.exs
        .version
        README.md
        LICENSE
      )
```

- [ ] **Step 2: Package the three existing derived plugins**

Run:
```bash
mix capstone.plugin.derive cache
mix capstone.plugin.derive openapi
mix capstone.plugin.derive prod_image_api
mix capstone.plugin.package cache
mix capstone.plugin.package openapi
mix capstone.plugin.package prod_image_api
```

Expected: three new files under `priv/plugins/`, each named
`<type>-<elixir>-<capstone>-<sha>.tar.gz`.

- [ ] **Step 3: Confirm the resolver finds them for real**

Run:
```bash
mix run -e 'IO.inspect(Capstone.Plugin.Registry.resolve!(:cache, System.version(), Capstone.MixProject.project()[:version], Capstone.Plugin.Registry.default_dir()))'
```

Expected: prints the path to the just-packaged `cache-...tar.gz`.

- [ ] **Step 4: Run the full suite and gates**

Run: `mix test && mix format --check-formatted && mix credo --strict && mix dialyzer && mix doctor && mix coveralls`
Expected: all pass; `mix coveralls` still reports 100% (packaged `.tar.gz`
binaries are not `.ex` source, so they don't enter the coverage report at
all).

- [ ] **Step 5: Confirm the package still builds as an archive**

Run: `mix archive.build -o /tmp/capstone-check.ez && unzip -l /tmp/capstone-check.ez | grep priv/plugins`
Expected: the three archives are listed inside the built `.ez`. Then
`rm /tmp/capstone-check.ez`.

- [ ] **Step 6: Commit**

```bash
git add mix.exs priv/plugins
git commit -m "feat(plugin): ship priv/plugins/ in the package; seed cache, openapi, prod_image_api"
```

---

### Task 11: End-to-end integration — real `mix capstone.new` and `mix capstone.update` with a real plugin

**Files:**
- Modify: `test/integration/target_project_test.exs`
- Create: `test/integration/plugin_lifecycle_test.exs`

**Interfaces:**
- Consumes: everything above, against the REAL `priv/plugins/cache-*.tar.gz` seeded in Task 10 (no fakes).

- [ ] **Step 1: Write the failing end-to-end test**

```elixir
defmodule Capstone.Integration.PluginLifecycleTest do
  @moduledoc """
  Exercises the real registry seeded in priv/plugins/ end to end: a project
  generated with plugins: [:cache] carries the cache plugin's files from the
  first `mix capstone.new`, and a second project generated with no plugins
  gains them afterward via `mix capstone.update`.
  """

  use ExUnit.Case, async: false

  alias Capstone.New.Bootstrap
  alias Capstone.New.Options
  alias Capstone.Update

  @tag :toolchain
  @tag :tmp_dir
  test "mix capstone.new applies plugins: [:cache] from target.exs", %{tmp_dir: tmp} do
    name = Path.join(tmp, "with_cache")

    opts = %Options{
      name: name,
      app: :with_cache,
      module: WithCache,
      base: :otp,
      github_org: "acme",
      capstone: {:path, File.cwd!()},
      plugins: [:cache]
    }

    assert :ok = Bootstrap.run(opts, Bootstrap.defaults())
    assert File.exists?(Path.join(name, "target.exs"))
    # Assert on whichever file(s) `priv/meta/meta_cache/` records as
    # :sole_owner — read priv/meta/meta_cache/manifest.exs to name one
    # concretely rather than guessing here.
  end

  @tag :toolchain
  @tag :tmp_dir
  test "mix capstone.update applies a plugin added to an existing project's target.exs", %{
    tmp_dir: tmp
  } do
    name = Path.join(tmp, "no_cache_yet")

    opts = %Options{
      name: name,
      app: :no_cache_yet,
      module: NoCacheYet,
      base: :otp,
      github_org: "acme",
      capstone: {:path, File.cwd!()},
      plugins: []
    }

    assert :ok = Bootstrap.run(opts, Bootstrap.defaults())

    target_exs = Path.join(name, "target.exs")
    File.write!(target_exs, String.replace(File.read!(target_exs), "plugins: []", "plugins: [:cache]"))

    assert {:ok, [:cache]} = Update.run(name, Capstone.Plugin.Registry.default_dir())
  end
end
```

- [ ] **Step 2: Fill in the concrete cache-plugin assertion**

Run `cat priv/meta/meta_cache/manifest.exs` to find one `:sole_owner` path,
and replace the placeholder comment in the first test with a real
`assert File.exists?(Path.join(name, "<that path>"))`.

- [ ] **Step 3: Run to verify it fails first, then passes**

Run: `mix test --include toolchain test/integration/plugin_lifecycle_test.exs`
Expected: FAILs before this task's prior tasks are all merged into this
branch/history; PASSes once Tasks 1–10 are in place. (`:toolchain` is
excluded by default per `test/test_helper.exs` — this task's tests need
`mix new`/`mix phx.new` on the machine, same as every other `:toolchain`
test in this suite.)

- [ ] **Step 4: Full suite including toolchain tests, and all gates**

Run: `mix test --include toolchain && mix format --check-formatted && mix credo --strict && mix dialyzer && mix doctor && mix coveralls`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add test/integration/plugin_lifecycle_test.exs
git commit -m "test(integration): exercise mix capstone.new/update against the real cache plugin"
```

---

## Self-Review Notes

- **Spec coverage:** naming/storage (Tasks 1, 10), packaging (Task 1),
  resolution (Task 3), retirement (Task 4), `target.exs`/`Config` schema
  (Task 7), `capstone.new` application (Task 8), `capstone.update` (Task 9),
  testing conventions (every task's Test files, plus Task 11's end-to-end
  coverage) are each covered by a task above.
- **Deviations from the written spec**, both already called out inline where
  they arise: (1) `origin` gains a `{:registry, filename}` variant instead of
  a separate `archive` field, and needs no `plugin.exs` schema-version bump
  (Task 5); (2) `retired.exs` is map-rooted (`%{retired: [...]}`) rather than
  a bare list, so it can go through the existing `Capstone.Source`
  encode/decode pair instead of a new parser (Task 4).
- **Ordering:** Tasks 1→11 are a dependency chain (Package before Registry
  before Install before Bootstrap/Update before the real seeded registry
  before end-to-end tests) — execute in order; do not parallelize across
  tasks even under subagent-driven-development, since each later task's code
  examples call functions the previous task defines.
