# Web Layer Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the `web_layer` plugin (Phoenix LiveView + Svelte 5 + `sv5ui` + Vite via `phoenix_vite` + `pnpm`) from `wimwian-org/svelixir`, register and derive/compose it through capstone's existing plugin pipeline, and wire `target.exs`'s `base: :web`/`base: :both` to auto-apply it — a mechanism neither capstone nor svelixir has built yet.

**Architecture:** `priv/meta/web_component/` (ported verbatim from svelixir, already `new_api_app`/`NewApiApp`-identified) → `mix capstone.plugin.derive web_layer` → `priv/meta/meta_web_layer/manifest.exs` → `mix capstone.baseline.compose web` (existing `Mix.Tasks.Capstone.Baseline.Compose`, whose own moduledoc already uses `web` as its worked example) → checked-in `priv/meta/baseline_web/`. Separately, `Capstone.New.Options.from_config!/1` gains a pure `implied_plugins/1` lookup so `base: :web`/`:both` prepend `:web_layer` to the plugins list before `Capstone.New.Bootstrap` ever runs — `Bootstrap`, `Capstone.Plugin.Install`, `Apply`, and `Record` need zero changes, since they already only ever look at `opts.plugins` generically.

**Tech Stack:** Elixir 1.20, Phoenix 1.8/`phoenix_live_view ~> 1.0`, `live_svelte ~> 0.18`, `phoenix_vite ~> 0.5`, `pnpm`.

**Spec:** `docs/superpowers/specs/2026-08-29-web-plugin-design.md`

## Global Constraints

- The plugin is built via the existing pipeline: `priv/meta/web_component/` (ported, not hand-edited) → `mix capstone.plugin.derive web_layer` → `priv/meta/meta_web_layer/manifest.exs`. Never hand-edit files under `priv/meta/meta_web_layer/` directly.
- `priv/meta/web_component/` already carries the `new_api_app`/`NewApiApp` identity — confirmed directly against svelixir's own `priv/meta/web_component/mix.exs` (`app: :new_api_app`, `defmodule NewApiApp.MixProject`). **No identity rename at port time.** Only the composed `priv/meta/baseline_web` gets renamed (to `new_web_app`/`NewWebApp`), and that happens automatically inside `mix capstone.baseline.compose web` (`Template.capture/2`/`render/2`) — already-implemented, already-tested capstone machinery, unchanged by this work.
- `priv/baselines.exs` needs two new top-level keys, not one: `web_layer` (`derived_from: :api, path: "priv/meta/web_component"` — the raw component `derive` reads) and `web` (`derived_from: :api, plugin: :web_layer, path: "priv/meta/baseline_web", names: %{app: "new_web_app", module: "NewWebApp", name: "new_web_app"}` — the composed baseline `compose` writes and `record`/the drift-check test read). Confirm the `names:` field before running `compose` — `Mix.Tasks.Capstone.Baseline.Compose`'s `rename!/2` dereferences `entry.names` unconditionally and raises a `KeyError` (not a clean `Mix.raise`) without it.
- `Capstone.Baseline`'s existing pruning (`@pruned` includes `node_modules`; `@pruned_paths` includes `mix.lock`, `priv/static/assets/`, `priv/static/.vite/`) already closes the "derive chokes on installed packages" bug svelixir's own port had to discover the hard way — do not re-add any of these paths to a manifest by hand if `derive` skips them; that's correct, not a bug.
- Phase B's implication lives ONLY in `Capstone.New.Options.from_config!/1` (a new `implied_plugins/1` function + `@base_plugins` map) — never in `Capstone.New.Bootstrap` (which must stay ignorant that `:web_layer` is special) and never read live from `priv/baselines.exs`/`priv/meta/` at runtime (neither ships inside the hex package an end user's project actually depends on — `Capstone.Plugin.Remote`'s own moduledoc is explicit that `priv/plugins/` is never shipped, and the same reasoning applies to `priv/baselines.exs`/`priv/meta/`).
- `Capstone.Config.t()`'s `base` type is `:api | :web | :both` (never `:otp` — `Capstone.Config`'s `@valid_bases` has never included it, unaffected by this work). `implied_plugins/1`'s spec should use that same union, not `Capstone.New.Options.base()` (which is the broader `:otp | :api | :web | :both` used only for the generator-selection concern) — `implied_plugins/1` is only ever called with `config.base`, which can never be `:otp`.
- `Options.from_config!/1`'s changed `plugins:` line is `(implied_plugins(config.base) ++ config.plugins) |> Enum.uniq()` — implied first, `Enum.uniq/1` keeps first occurrence, so an explicit duplicate in `target.exs` never double-applies. Nothing today orders plugin application by list position (`Capstone.Manifest`'s `encode!/1` sorts plugins by name on write), so this ordering choice has no behavioral effect beyond being an explicit, intentional rule rather than an accidental one.
- Two existing tests hard-code `base: :web`'s current (pre-Phase-B) behavior and WILL break once `from_config!/1` changes, because `Capstone.New.Factory.config_factory/0`'s default `base` is `:web` (`test/support/new_factory.ex:72`): `test/capstone/new/options_test.exs`'s `"from_config!/1 maps a %Capstone.Config{} directly"` (line 62) and `"from_config!/1 carries the config's plugins list through"` (line 78) both build `Factory.build(:config, ...)` without overriding `base` and assert `opts.plugins` equals `config.plugins` exactly. Task 7 fixes both by pinning `base: :api` explicitly (implies nothing), so they stay focused on field-mapping/pass-through rather than accidentally coupling to base-implication semantics.
- `test/integration/target_project_test.exs`'s `@tag :toolchain test "drives phx.new with the flags that keep HTML and assets out, for :api and :both"` (line 254) currently asserts, for BOTH `:api` and `:both`, that no `assets/` directory and no `core_components.ex` exist after a full `generate!/2` run. That assertion is correct today (nothing applies a web-layer plugin yet) and becomes wrong for `:both` once Phase B ships — `:both` will then genuinely gain `assets/`/`core_components.ex` via the implied `:web_layer` plugin. Task 8 splits `:both` out of that test rather than flipping its assertion in place, since the test's own name ("the flags that keep HTML and assets out") is really about the STOCK GENERATOR step (`Options.generator_argv/1`, unchanged by this work), not about final post-plugin state — conflating the two in one shared loop is exactly what breaks once `:both` and `:api` diverge in final state.
- Any `--include toolchain` test that applies `:web_layer` via `Bootstrap.run/2` (directly or via the `base:` implication) needs `:web_layer` locally packaged first if it isn't published yet by the time these tasks run: `mix capstone.plugin.package web_layer`, copy the resulting `priv/plugins/web_layer-*.tar.gz` into `~/Library/Caches/capstone/plugins/`, removing any other `web_layer-*.tar.gz` already there first (a same-version/lexicographic-sha tiebreak bug was found doing exactly this for `:grpc` on an earlier branch — always keep only the freshly-packaged archive).
- A toolchain test's final `mix compile`/`mix test` smoke check inside a generated project must run via `Shell.cmd!(["test"], project)` (or the file-based helpers this test file already uses), never `Shell.cmd!(["run", "-e", "..."], project)` — `Shell.cmd!/3` scrubs `MIX_ENV` for every child invocation and cannot be told to use a specific non-default env; only `mix test`'s own `preferred_cli_env` reliably reaches `:test`. A real, hard-won lesson from an earlier plugin's plan on this project — do not repeat the `mix run -e` mistake.
- The structural toolchain tests in this plan additionally need `pnpm` on the toolchain machine (`assets.setup`/`assets.build` shell out to it) — if `pnpm` isn't found, the test should fail with a clear message naming the missing binary, the same way the existing suite already gates other `:toolchain` tests on `mix new`/`mix phx.new`/`protoc` being installed, rather than hanging or failing opaquely.
- `web`'s own composed baseline (`priv/meta/baseline_web`) is a maintainer-only drift-check fixture — it is never packaged or published. Only `web_layer` (packaged from `priv/meta/meta_web_layer/`) is what a real `mix capstone.new` run downloads and applies.

---

## File Structure

**`:web_layer` plugin** (ported into `priv/meta/web_component/`; `priv/meta/meta_web_layer/` regenerated by `derive`; `priv/meta/baseline_web/` regenerated by `compose`):
- Copy the entire `priv/meta/web_component/` tree from `/Users/pancha/code/elixir/archive/svelixir/priv/meta/web_component/`.

**Capstone's own repo:**
- Modify `priv/baselines.exs` — new `web_layer` and `web` entries, `files`/`tree_digest`/`archive_sha256` filled in by `mix capstone.baseline.record`.
- Create `test/capstone/plugin/web_layer_round_trip_test.exs`.
- Modify `test/capstone/baseline_test.exs` — new offline compose-drift-check test for `web`.
- Modify `test/integration/plugin_lifecycle_test.exs` — new `:web_layer` structural toolchain test (explicit `plugins: [:web_layer]`).
- Modify `lib/capstone/new/options.ex` — `implied_plugins/1`, `@base_plugins`, changed `from_config!/1`.
- Modify `test/capstone/new/options_test.exs` — pin `base: :api` on the two now-affected tests; add implication unit tests.
- Modify `test/integration/target_project_test.exs` — split `:both` out of the existing HTML/assets toolchain test; add a new toolchain test proving `base: :web`/`:both` auto-apply `:web_layer` with no explicit `plugins:` entry.

---

### Task 1: Port `priv/meta/web_component/` and verify it standalone

**Files:**
- Create: `priv/meta/web_component/` (entire tree, copied from svelixir)

**Interfaces:**
- Produces: `priv/meta/web_component/` — the raw source Task 2's `derive` reads.

- [ ] **Step 1: Copy the tree**

```bash
rm -rf priv/meta/web_component
cp -r /Users/pancha/code/elixir/archive/svelixir/priv/meta/web_component priv/meta/web_component
rm -rf priv/meta/web_component/_build priv/meta/web_component/deps
```

- [ ] **Step 2: Confirm identity needs no changes**

```bash
grep -n "app:\|defmodule NewApiApp" priv/meta/web_component/mix.exs
```

Expected: `app: :new_api_app`, `defmodule NewApiApp.MixProject`. If this shows anything else,
STOP — the source tree copied is not what this plan assumes; re-check the source path before
continuing.

- [ ] **Step 3: Verify it compiles and its own tests pass standalone**

```bash
cd priv/meta/web_component
mix deps.get
mix compile --warnings-as-errors
mix test
cd -
```

If compilation fails, the likely cause is drift between svelixir's `baseline_api` and capstone's
current `baseline_api` (different `generator_version`/Elixir/Phoenix pins) — diff
`priv/meta/web_component/mix.exs`'s Phoenix-family deps against capstone's own
`priv/meta/baseline_api/mix.exs` and adjust `web_component`'s versions to match capstone's
current baseline, not the other way around (Global Constraints: never bump `baseline_api` to
chase this).

If `mix deps.get`/`mix compile` needs `pnpm`/asset setup to succeed, run
`mix assets.setup && mix assets.build` inside `priv/meta/web_component` first — check its
`mix.exs` aliases (ported in Step 1) for the exact alias name before assuming `assets.setup` is
correct.

- [ ] **Step 4: Remove build artifacts before committing**

```bash
rm -rf priv/meta/web_component/_build priv/meta/web_component/deps priv/meta/web_component/assets/node_modules
git status --porcelain priv/meta/web_component | head -30
```

Confirm nothing under `_build/`, `deps/`, or `node_modules/` is about to be staged — `derive`
already prunes these from its own tree walk, but committing them anyway would bloat the repo for
no reason.

- [ ] **Step 5: Commit**

```bash
git add priv/meta/web_component
git commit -m "feat(plugin): port web_component from wimwian-org/svelixir"
```

---

### Task 2: Register and derive `:web_layer`

**Files:**
- Modify: `priv/baselines.exs`
- Create: `priv/meta/meta_web_layer/manifest.exs`, `priv/meta/meta_web_layer/files/*.eex` (all `derive` output — do not hand-author)

**Interfaces:**
- Consumes: `priv/meta/web_component/` (Task 1).
- Produces: `priv/meta/meta_web_layer/manifest.exs`, consumed by Task 3 (`compose`), Task 4
  (round-trip test), Task 6 (structural toolchain test).

- [ ] **Step 1: Add the `web_layer` entry to `priv/baselines.exs`**

Add, alongside the existing `openapi:`/`prod_image_api:` entries (alphabetical by key, matching
the file's existing order):

```elixir
web_layer: %{derived_from: :api, path: "priv/meta/web_component"},
```

- [ ] **Step 2: Derive**

```bash
mix capstone.plugin.derive web_layer
```

Expected: `wrote priv/meta/meta_web_layer/manifest.exs` plus a file/dep count.

- [ ] **Step 3: Inspect the manifest for correctness**

```bash
cat priv/meta/meta_web_layer/manifest.exs
```

Verify, per the design spec's §"What ports from svelixir":
- `deps:` contains exactly three entries: `phoenix_vite`, `phoenix_live_view`, `live_svelte`.
- `aliases:` contains the nine `assets.*` entries plus `setup` gaining `"assets.setup"`.
- Every new `assets/`, `lib/mix/tasks/assets.pnpm.ex`, `lib/new_api_app/vite_watcher.ex`,
  `lib/new_api_app_web/components/*`, `mix.lock`, and built `priv/static/.vite/`/hashed-asset
  file appears as `{"...", :sole_owner}`.
- `config/config.exs` and `config/dev.exs` appear as `:contributes`.
- `lib/new_api_app_web.ex`, `lib/new_api_app_web/endpoint.ex`, `lib/new_api_app_web/router.ex`
  each appear as exactly ONE contiguous `:manual` hunk — NOT split into multiple insertions for
  the same file. If any of the three shows more than one hunk, STOP: svelixir's own `7aa7f30`
  commit hit and fixed this exact failure mode by consolidating the component's edits into one
  contiguous insertion per file before deriving; re-check `web_component`'s edits to those three
  files for a stray second, separated insertion and consolidate it before re-deriving.

- [ ] **Step 4: Re-derive every other plugin, confirming no diff**

```bash
mix capstone.plugin.derive cache
mix capstone.plugin.derive cqrs
mix capstone.plugin.derive grpc
mix capstone.plugin.derive openapi
mix capstone.plugin.derive prod_image_api
git diff --stat priv/meta/meta_cache priv/meta/meta_cqrs priv/meta/meta_grpc priv/meta/meta_openapi priv/meta/meta_prod_image_api
```

Expected: no diff — this task's work is additive, unrelated plugins shouldn't move.

- [ ] **Step 5: Commit**

```bash
git add priv/meta/meta_web_layer priv/baselines.exs
git commit -m "feat(plugin): derive the :web_layer manifest"
```

---

### Task 3: Register and compose `:web`

**Files:**
- Modify: `priv/baselines.exs`
- Create: `priv/meta/baseline_web/` (entire composed tree — `compose` output, do not hand-author)

**Interfaces:**
- Consumes: `priv/meta/meta_web_layer/manifest.exs`, `priv/baselines.exs`'s `api`/`web_layer`
  entries (Task 2).
- Produces: `priv/meta/baseline_web/`, consumed by Task 5 (offline drift-check test).

- [ ] **Step 1: Add the `web` entry to `priv/baselines.exs`**

```elixir
web: %{
  derived_from: :api,
  plugin: :web_layer,
  path: "priv/meta/baseline_web",
  names: %{app: "new_web_app", module: "NewWebApp", name: "new_web_app"}
},
```

`names:` is required — `Mix.Tasks.Capstone.Baseline.Compose`'s `rename!/2` dereferences
`entry.names` unconditionally (see Global Constraints).

- [ ] **Step 2: Compose**

```bash
mix capstone.baseline.compose web
```

Expected: `composed priv/meta/baseline_web from priv/meta/baseline_api + priv/meta/meta_web_layer`.

- [ ] **Step 3: Verify the composed tree's identity and shape**

```bash
grep -n "app:\|defmodule" priv/meta/baseline_web/mix.exs
ls priv/meta/baseline_web/assets
test -f priv/meta/baseline_web/lib/new_web_app_web/components/core_components.ex && echo OK
```

Expected: `app: :new_web_app`, `defmodule NewWebApp.MixProject`, the `assets/` directory present,
`core_components.ex` renamed under `new_web_app_web/` (not `new_api_app_web/`).

- [ ] **Step 4: Compose is idempotent**

```bash
mix capstone.baseline.compose web
git status --porcelain priv/meta/baseline_web
```

Expected: no changes — re-composing an unchanged source must reproduce byte-identical output
(this is what makes Task 5's offline drift-check test meaningful rather than flaky).

- [ ] **Step 5: Record real baseline hashes for both new entries**

```bash
mix capstone.baseline.record
```

- [ ] **Step 6: Verify both new `priv/baselines.exs` entries look sane**

```bash
mix run -e '
manifest = Capstone.Baseline.read!("priv/baselines.exs")
IO.inspect(manifest.web_layer.derived_from)
IO.inspect(map_size(manifest.web_layer.files))
IO.inspect(manifest.web.derived_from)
IO.inspect(manifest.web.plugin)
IO.inspect(map_size(manifest.web.files))
'
```

Expected: `:api`, a file count matching Task 2's manifest inspection; `:api`, `:web_layer`, a
file count matching `baseline_api`'s file count plus `web_layer`'s new/changed files.

- [ ] **Step 7: Commit (leave the root snapshot archives untracked for Task 9)**

```bash
git add priv/meta/baseline_web priv/baselines.exs
git status --porcelain  # confirm the *_*.tar.gz files show as untracked (??), not staged
git commit -m "feat(baseline): compose the web baseline from api plus web_layer"
```

---

### Task 4: Round-trip test for `:web_layer`

**Files:**
- Create: `test/capstone/plugin/web_layer_round_trip_test.exs`

**Interfaces:**
- Consumes: `priv/meta/meta_web_layer/manifest.exs`, `priv/meta/web_component/` (Task 2).

- [ ] **Step 1: Write the test file**

Modeled on `test/capstone/plugin/grpc_round_trip_test.exs`'s shape (adjust if `:web_layer`'s
`:manual` hunks make the base-reproduction case behave differently — check Task 2 Step 3's
inspection first):

```elixir
defmodule Capstone.Plugin.WebLayerRoundTripTest do
  # async: false — copies real trees under priv/meta.
  use ExUnit.Case, async: false

  alias Capstone.Baseline
  alias Capstone.Plugin.Apply

  @baseline "priv/meta/baseline_api"
  @plugin "priv/meta/meta_web_layer"
  @raw "priv/meta/web_component"

  setup do
    target =
      Path.join(System.tmp_dir!(), "web-layer-round-trip-#{System.unique_integer([:positive])}")

    File.cp_r!(@baseline, target)
    on_exit(fn -> File.rm_rf!(target) end)

    {:ok, target: target}
  end

  test "applying meta_web_layer to baseline_api reproduces web_component", %{target: target} do
    {:ok, _plugin} = Apply.run(@plugin, target)

    expected = Baseline.tree(@raw)
    actual = Baseline.tree(target)

    differing = for {path, hash} <- expected, actual[path] != hash, do: path

    assert differing == []
    assert Enum.sort(Map.keys(actual)) == Enum.sort(Map.keys(expected))
  end

  test "applying twice is a no-op", %{target: target} do
    {:ok, _} = Apply.run(@plugin, target)
    once = Baseline.tree(target)

    {:ok, _} = Apply.run(@plugin, target)

    assert Baseline.tree(target) == once
  end

  test "the plugin installs into a differently named project" do
    other = Path.join(System.tmp_dir!(), "web-layer-other-#{System.unique_integer([:positive])}")
    File.cp_r!(@baseline, other)
    on_exit(fn -> File.rm_rf!(other) end)

    mix = Path.join(other, "mix.exs")
    File.write!(mix, String.replace(File.read!(mix), ":new_api_app", ":other_app"))

    root = Path.join(other, "lib/new_api_app.ex")

    File.write!(
      Path.join(other, "lib/other_app.ex"),
      String.replace(File.read!(root), "NewApiApp", "OtherApp")
    )

    File.rm!(root)
    File.rename!(Path.join(other, "lib/new_api_app"), Path.join(other, "lib/other_app"))

    for file <- Path.wildcard(Path.join(other, "lib/other_app/**/*.ex")) do
      File.write!(file, String.replace(File.read!(file), "NewApiApp", "OtherApp"))
    end

    for file <- Path.wildcard(Path.join(other, "lib/other_app_web/**/*.{ex,heex}")) do
      File.write!(file, String.replace(File.read!(file), "NewApiAppWeb", "OtherAppWeb"))
    end

    {:ok, _} = Apply.run(@plugin, other)

    assert File.exists?(Path.join(other, "lib/other_app/vite_watcher.ex"))
    refute File.exists?(Path.join(other, "lib/new_api_app/vite_watcher.ex"))
  end
end
```

The third test's file list (`lib/other_app_web/**/*.{ex,heex}`) is broader than `:grpc`'s
equivalent test needed, since `:web_layer` ships `.heex` templates in addition to `.ex` — confirm
`root.html.heex`'s renamed path is covered; adjust the wildcard if Task 2's manifest inspection
showed a path this doesn't match.

- [ ] **Step 2: Run it**

```bash
mix test test/capstone/plugin/web_layer_round_trip_test.exs
```

Expected: 3/3 PASS. If the base-reproduction test fails, the failure names the differing file
path — re-check Task 2's manifest inspection rather than patching this test to match a wrong
reproduction.

- [ ] **Step 3: Commit**

```bash
git add test/capstone/plugin/web_layer_round_trip_test.exs
git commit -m "test(plugin): add a round-trip test for the :web_layer plugin"
```

---

### Task 5: Offline compose drift-check test for `:web`

**Files:**
- Modify: `test/capstone/baseline_test.exs`

**Interfaces:**
- Consumes: `priv/baselines.exs`'s `web`/`web_layer`/`api` entries, `priv/meta/baseline_web/`
  (Task 3).

This mirrors svelixir's own `519baed` commit, which replaced a live-generator toolchain test with
exactly this — fully offline, both inputs checked in, so it runs on every commit rather than only
where a generator toolchain is installed.

- [ ] **Step 1: Add the test**

Insert into `test/capstone/baseline_test.exs`, near the other baseline-shape tests (e.g. after
`"a derived entry carries no generator provenance"`). This calls the REAL
`Mix.Tasks.Capstone.Baseline.Compose.run/1` against its real, already-tracked
`priv/meta/baseline_web` path (never a scratch copy) and asserts it reproduces byte-identical
output — Task 3 Step 4 already proved `compose` is idempotent by hand; this is that same proof,
turned into a permanent, always-run test. No private logic is duplicated: the test exercises the
actual command a maintainer runs, not a reimplementation of its internals. Add
`import ExUnit.CaptureIO` to this test module if it isn't already imported (check the top of the
file first — `test/mix/tasks/capstone.baseline.compose_test.exs` already does this and can be
used as the reference for the exact import form).

```elixir
test "composing :web from :api plus :web_layer reproduces the checked-in baseline_web" do
  web = Map.fetch!(Baseline.read!("priv/baselines.exs"), :web)
  before = Baseline.tree(web.path)

  capture_io(fn -> Mix.Tasks.Capstone.Baseline.Compose.run(["web"]) end)

  assert_same_tree(Baseline.tree(web.path), before)
end
```

If this assertion ever fails, `priv/meta/baseline_web` is left modified on disk by the failing
`Compose.run/1` call — that dirty working tree IS the debugging signal (same as Task 3 Step 4),
not a side effect to suppress with an `on_exit` restore.

- [ ] **Step 2: Run it**

```bash
mix test test/capstone/baseline_test.exs -k "composing :web"
```

Expected: PASS, with no `:toolchain` tag needed (fully offline).

- [ ] **Step 3: Commit**

```bash
git add test/capstone/baseline_test.exs
git commit -m "test(baseline): add an offline compose drift-check test for :web"
```

---

### Task 6: `:web_layer` structural toolchain test

**Files:**
- Modify: `test/integration/plugin_lifecycle_test.exs`

**Interfaces:**
- Consumes: `priv/baselines.exs`'s `web_layer` entry, `priv/meta/meta_web_layer/manifest.exs`
  (Task 2).

Per Global Constraints, this needs the local-packaging workaround if `:web_layer` isn't published
yet: `mix capstone.plugin.package web_layer`, copy the archive into
`~/Library/Caches/capstone/plugins/`, removing any stale same-plugin archives there first.

This test proves the PLUGIN works via explicit `plugins: [:web_layer]` — independent of Phase B's
`base:`-implication mechanism, which Task 8 tests separately.

- [ ] **Step 1: Add the toolchain test**

Insert into `test/integration/plugin_lifecycle_test.exs`, after the existing toolchain tests:

```elixir
  @tag :toolchain
  @tag timeout: :timer.minutes(3)
  test "mix capstone.new applies plugins: [:web_layer] from target.exs", %{tmp_dir: tmp} do
    capstone_path = File.cwd!()
    name = "with_web_layer"

    opts = %Options{
      name: name,
      app: :with_web_layer,
      module: WithWebLayer,
      base: :api,
      github_org: "acme",
      capstone: {:path, capstone_path},
      plugins: [:web_layer]
    }

    File.cd!(tmp, fn -> assert :ok = Bootstrap.run(opts, Bootstrap.defaults()) end)

    project = Path.join(tmp, name)
    assert File.exists?(Path.join(project, "target.exs"))
    assert File.exists?(Path.join(project, "assets/svelte/components/AppShell.svelte"))
    assert File.exists?(Path.join(project, "lib/with_web_layer_web/components/core_components.ex"))
    assert File.exists?(Path.join(project, "lib/with_web_layer/vite_watcher.ex"))

    Shell.cmd!(["compile"], project)
    Shell.cmd!(["test"], project)
  end
```

`base: :api` here is deliberate: this test proves the plugin applies correctly when explicitly
requested, regardless of base — it must NOT rely on Phase B's implication (Task 7/8), which isn't
built yet at this point in the plan.

- [ ] **Step 2: Run it**

```bash
mix test test/integration/plugin_lifecycle_test.exs --include toolchain
```

Expected: PASS. Budget several minutes — the inner run does its own `deps.get`/`deps.compile`
plus `assets.setup` (pnpm install).

- [ ] **Step 3: Commit**

```bash
git add test/integration/plugin_lifecycle_test.exs
git commit -m "test(plugin): add a structural toolchain test for the :web_layer plugin"
```

---

### Task 7: Implement `base:` → implied-plugin wiring

**Files:**
- Modify: `lib/capstone/new/options.ex`
- Modify: `test/capstone/new/options_test.exs`

**Interfaces:**
- Consumes: `Capstone.Config.t()` (`base`, `plugins` fields).
- Produces: `Capstone.New.Options.implied_plugins/1`, consumed by `from_config!/1` and by
  Task 8's toolchain test's expectations.

- [ ] **Step 1: Add `implied_plugins/1` and change `from_config!/1`**

In `lib/capstone/new/options.ex`, add near the top (after `@default_requirement`):

```elixir
@base_plugins %{web: [:web_layer], both: [:web_layer]}
```

Add a new public function (after `parse!/1`, before `from_config!/1`):

```elixir
@doc """
Plugins `base` implies, in addition to whatever `target.exs` lists explicitly.

`:api` implies nothing — it is the bare tree every other base is generated
from and derived against. `:web` and `:both` both imply `:web_layer`: the
LiveView/Svelte layer never comes from the generator (`generator_argv/1`
strips `--no-html --no-assets` for all three phx.new-driven bases
identically), only from this plugin being applied.
"""
@spec implied_plugins(:api | :web | :both) :: [atom()]
def implied_plugins(base), do: Map.get(@base_plugins, base, [])
```

Change `from_config!/1`'s body from:

```elixir
      capstone: {:hex, @default_requirement},
      plugins: config.plugins
    }
```

to:

```elixir
      capstone: {:hex, @default_requirement},
      plugins: (implied_plugins(config.base) ++ config.plugins) |> Enum.uniq()
    }
```

- [ ] **Step 2: Fix the two existing tests this changes the behavior of**

In `test/capstone/new/options_test.exs`, change `"from_config!/1 maps a %Capstone.Config{} directly"`:

```elixir
  test "from_config!/1 maps a %Capstone.Config{} directly" do
    config = %{Factory.build(:config) | base: :api}

    opts = Options.from_config!(config)

    assert opts == %Options{
             name: config.project.name,
             app: config.project.app,
             module: config.project.module,
             base: config.base,
             github_org: config.project.github_org,
             capstone: {:hex, "~> 0.1"},
             plugins: config.plugins
           }
  end
```

and `"from_config!/1 carries the config's plugins list through"`:

```elixir
  test "from_config!/1 carries the config's plugins list through" do
    config = Factory.build(:config, base: :api, plugins: [:cache])

    assert Options.from_config!(config).plugins == [:cache]
  end
```

Both now pin `base: :api` explicitly (implies nothing), so they stay about field-mapping and
pass-through rather than accidentally depending on `Factory`'s default `base: :web`
(`test/support/new_factory.ex:72`).

- [ ] **Step 3: Add implication-specific tests**

Add after the two fixed tests above:

```elixir
  describe "from_config!/1 — base-implied plugins" do
    test "base: :web prepends :web_layer" do
      config = Factory.build(:config, base: :web, plugins: [])

      assert Options.from_config!(config).plugins == [:web_layer]
    end

    test "base: :both prepends :web_layer" do
      config = Factory.build(:config, base: :both, plugins: [])

      assert Options.from_config!(config).plugins == [:web_layer]
    end

    test "base: :api implies nothing" do
      config = Factory.build(:config, base: :api, plugins: [:cache])

      assert Options.from_config!(config).plugins == [:cache]
    end

    test "an explicit :web_layer entry does not duplicate the implied one" do
      config = Factory.build(:config, base: :web, plugins: [:web_layer, :cache])

      assert Options.from_config!(config).plugins == [:web_layer, :cache]
    end

    test "implied plugins come before explicit ones" do
      config = Factory.build(:config, base: :web, plugins: [:cache])

      assert Options.from_config!(config).plugins == [:web_layer, :cache]
    end
  end

  describe "implied_plugins/1" do
    test "returns [] for :api" do
      assert Options.implied_plugins(:api) == []
    end

    test "returns [:web_layer] for :web and :both" do
      assert Options.implied_plugins(:web) == [:web_layer]
      assert Options.implied_plugins(:both) == [:web_layer]
    end
  end
```

- [ ] **Step 4: Run the affected tests**

```bash
mix test test/capstone/new/options_test.exs
```

Expected: all PASS.

- [ ] **Step 5: Run the full non-toolchain suite to catch any other fallout**

```bash
mix test
```

Fix anything that surfaces before continuing — the Global Constraints section flags the two
known-affected tests fixed in Step 2 and the toolchain test Task 8 fixes next, but confirm no
other test implicitly depends on `base: :web`'s old (unimplied) `plugins` behavior.

- [ ] **Step 6: Commit**

```bash
git add lib/capstone/new/options.ex test/capstone/new/options_test.exs
git commit -m "feat(new): imply :web_layer for base: :web and :both"
```

---

### Task 8: Fix and extend the base-level toolchain tests

**Files:**
- Modify: `test/integration/target_project_test.exs`

**Interfaces:**
- Consumes: `Capstone.New.Options.implied_plugins/1` (Task 7), `priv/baselines.exs`'s
  `web_layer` entry (Task 2).

Needs the same local-packaging workaround as Task 6 if `:web_layer` isn't published yet.

- [ ] **Step 1: Split `:both` out of the existing HTML/assets test**

Read `test/integration/target_project_test.exs` around line 254
(`test "drives phx.new with the flags that keep HTML and assets out, for :api and :both"`)
before editing — this plan describes the change, not a verbatim replacement, since exact
surrounding line numbers may have shifted by the time this task runs.

Change the loop from `for base <- [:api, :both] do` to `for base <- [:api] do` and rename the
test to drop "and :both": `test "drives phx.new with the flags that keep HTML and assets out, for :api"`.
Leave everything else in the test body unchanged.

- [ ] **Step 2: Run the edited test to confirm it still passes for `:api` alone**

```bash
mix test test/integration/target_project_test.exs --include toolchain -k "keep HTML and assets out"
```

- [ ] **Step 3: Add the new `base:`-implication toolchain test**

Insert into the same `describe "generating via --path against the real target.exs reader"`
block, after the edited test from Step 1:

```elixir
    @tag :toolchain
    test "base: :web and base: :both auto-apply :web_layer with no explicit plugins:",
         %{dir: dir} do
      Mix.Local.append_archives()

      for base <- [:web, :both] do
        name = "app_#{base}_implied"
        config = Factory.build(:config)

        config = %{
          config
          | base: base,
            plugins: [],
            project: %{
              config.project
              | name: name,
                module: Module.concat([Macro.camelize(name)]),
                app: String.to_atom(name)
            }
        }

        project = generate!(dir, config)

        assert File.exists?(Path.join(project, "assets/svelte/components/AppShell.svelte"))

        assert File.exists?(
                 Path.join(project, "lib/#{name}_web/components/core_components.ex")
               )

        real_config = Capstone.Config.read!(Path.join(project, "target.exs"))
        assert real_config.plugins == []
      end
    end
```

Note the last assertion: `target.exs`'s own `plugins:` stays exactly what the user wrote
(`[]`) — the implication happens in `Options.from_config!/1`, downstream of `Capstone.Config`,
never mutating `target.exs` itself. `real_config.plugins == []` is the whole point of Task 7's
design (implication lives at the `Options` boundary, not baked back into the config file).

- [ ] **Step 4: Run it**

```bash
mix test test/integration/target_project_test.exs --include toolchain -k "auto-apply"
```

Expected: PASS. If `real_config.plugins` is NOT `[]`, something wrote the implied plugin back
into `target.exs` — re-check that `Project.render_config/1` is never called with the
implied-and-deduped list where it should be called with the config's own original list; per
`Capstone.New.Bootstrap.run/3`, `target.exs` is written from `Project.render_config(opts)` using
`opts` (the `%Options{}`, which DOES carry the implied plugins) — if this assertion fails,
STOP and re-read `Bootstrap.run/3` and `Project.render_config/1` together before patching
anything, since the design's stated intent (`target.exs` remains a hand-authored record of user
intent) may need an explicit decision reversal, not a quick fix.

- [ ] **Step 5: Commit**

```bash
git add test/integration/target_project_test.exs
git commit -m "test(new): cover base: :web/:both implying :web_layer end to end"
```

---

### Task 9: Package, publish, and run the full gate suite

**Files:** none new — packaging and verification only.

- [ ] **Step 1: Run the full local gate suite**

```bash
mix format --check-formatted
mix credo --strict
mix dialyzer
mix doctor
mix coveralls
mix test --include toolchain
```

Fix anything that fails before continuing.

- [ ] **Step 2: Package the plugin**

```bash
mix capstone.plugin.package web_layer
```

Expected: `wrote priv/plugins/web_layer-<elixir>-<capstone>-<sha>.tar.gz`. Confirm nothing new is
staged:

```bash
git status --porcelain priv/plugins/
```

- [ ] **Step 3: STOP — get explicit human sign-off before publishing**

Creating and uploading a GitHub release is a side effect visible to others, outside this
worktree. Present what's about to happen (the release notes, the files to upload — note this
release includes BOTH `web_layer`'s package AND every baseline's snapshot archives, per Task 3
Step 7's note about the root-level `*_<version>_*.tar.gz` files) and wait for confirmation before
proceeding.

- [ ] **Step 4: Determine the current version and create a GitHub release**

```bash
version=$(cat .version)
echo "$version"
gh release create "v$version" \
  --repo wimwian-org/capstone \
  --title "v$version" \
  --notes "A new :web_layer plugin - Phoenix LiveView + Svelte 5 + sv5ui + Vite (phoenix_vite/pnpm), ported from wimwian-org/svelixir. base: :web and base: :both in target.exs now auto-apply it." \
  --target dev
```

If a release for this exact version tag already exists, use `gh release upload "v$version" <files>`
against the existing release instead of `gh release create`.

- [ ] **Step 5: Upload the archive set**

```bash
gh release upload "v$version" ./*_"$version"_*.tar.gz --repo wimwian-org/capstone
gh release upload "v$version" priv/plugins/web_layer-*.tar.gz --repo wimwian-org/capstone
```

- [ ] **Step 6: Clean up the untracked root-level snapshot archives**

```bash
rm -f ./*_"$version"_*.tar.gz
git status --porcelain
```

- [ ] **Step 7: Final sanity check — verify the plugin downloads and applies from the release**

```bash
rm -rf ~/Library/Caches/capstone
mix run -e '
dir = Capstone.Plugin.Registry.default_dir()
Capstone.Plugin.Remote.sync!(:web_layer, dir)
IO.inspect(File.ls!(dir))
'
rm -rf ~/Library/Caches/capstone
```

Expected: the listed files include a `web_layer-*.tar.gz` matching the version just packaged.

- [ ] **Step 8: Final end-to-end check — a real `target.exs` with `base: :web` and no plugins**

```bash
rm -rf ~/Library/Caches/capstone
mkdir -p /tmp/web-e2e && cd /tmp/web-e2e
cat > target.exs <<'EOF'
%{
  schema_version: 1,
  base: :web,
  plugins: [],
  project: [name: "web_e2e", github_org: "acme", module: WebE2e, app: :web_e2e]
}
EOF
mix capstone.new --path target.exs
cd web_e2e && mix compile && mix test
cd /tmp && rm -rf web-e2e
```

Expected: the generated `web_e2e` project has `assets/svelte/components/AppShell.svelte`,
compiles, and passes its own tests — the full, real, end-user-facing path this plan exists to
build.

- [ ] **Step 9: Final commit if anything changed during gate fixes**

```bash
git status --porcelain
# If clean, nothing to commit.
# If Step 1 required fixes, commit them:
git add -A
git commit -m "chore(plugin): fix gate failures found while finishing the :web_layer plugin"
```
