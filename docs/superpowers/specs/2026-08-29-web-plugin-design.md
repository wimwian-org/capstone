# `web_layer` plugin + `base: :web`/`:both` auto-composition — design

Date: 2026-08-29
Status: approved, pending implementation plan

## Purpose

Two things, shipped together because neither is useful alone:

1. A new capstone plugin, `web_layer` (`derived_from: :api`), giving a generated project
   Phoenix LiveView plus a Svelte 5 frontend (via `live_svelte`), Vite-based asset packaging
   (via `phoenix_vite`, `pnpm`), and a starter `sv5ui`-based component shell. Built the same
   way every other plugin is: a full project tree under `priv/meta/web_component/`, diffed
   automatically by `mix capstone.plugin.derive web_layer` into
   `priv/meta/meta_web_layer/manifest.exs`.
2. The mechanism — new to capstone — that makes `target.exs`'s `base: :web` and `base: :both`
   actually produce a project with this plugin applied, rather than the bare API tree they
   silently produce today (`Capstone.New.Options.generator_argv/1`'s own moduledoc already
   documents this gap: "`:api`, `:web` and `:both` all produce the SAME stock tree... the asset
   pipeline arrives when that plugin is applied").

`:otp` is out of scope throughout: `Capstone.Config`'s target.exs schema has never accepted it,
and this work does not change that.

## Provenance

`priv/meta/web_component/` is ported from `/Users/pancha/code/elixir/archive/svelixir/`
(GitHub: `wimwian-org/svelixir`, the bare/current tip of the lineage
`fireside_svelixir → svelixir_v1..v4 → svelixir` — only bare `svelixir` shares capstone's
current `.exs`-config / `derived_from:` + `Compose`/`Derive` architecture; v1–v4 targeted an
abandoned TOML-config generator and are not a source for anything here).

svelixir already built and tested this exact plugin (commits `7aa7f30` "derive the web
component from the api baseline" and `519baed` "compose the web baseline from api plus the web
component") for its own `priv/meta/web_component/` → `priv/meta/meta_web_layer/` →
`priv/meta/baseline_web` pipeline. It never built a project-generation entry point at all (no
`mix svelixir.new`), so the plugin there exists purely for offline drift-checking — the
`base: :web` → auto-apply mechanism in this spec has no precedent to port and is new work.

capstone's own `Capstone.Baseline` module already carries the pruning fixes svelixir's `7aa7f30`
had to discover the hard way against a real asset-having component (`@pruned` includes
`node_modules`; `@pruned_paths` includes `mix.lock`, `priv/static/assets/`,
`priv/static/.vite/`) — so the "derive chokes on installed packages" failure mode svelixir hit
is already closed here.

## What ports from svelixir, verbatim in substance

`priv/meta/web_component/` vs `priv/meta/baseline_api/`, diffed:

**New files** (all `:sole_owner` in the derived manifest):
- `assets/` — Vite + pnpm + Svelte 5: `vite.config.mjs`, `package.json`, `pnpm-lock.yaml`,
  `svelte/components/AppShell.svelte`, `svelte/lib/sv5ui.js`, `css/{app,theme}.css`,
  eslint/prettier/tsconfig/vitest configs, one Svelte component test
- `lib/mix/tasks/assets.pnpm.ex`
- `lib/new_api_app/vite_watcher.ex` (+ test)
- `lib/new_api_app_web/components/{core_components.ex, layouts.ex, layouts/root.html.heex}`
- `mix.lock`, built `priv/static/.vite/manifest.json` + hashed assets

**Modified files** (each recorded as one contiguous `:manual` anchored hunk — svelixir's
`7aa7f30` found that a component's manifest holds exactly one anchored insertion per file, so
what was originally two separated insertions per file had to be consolidated first):
- `lib/new_api_app_web/endpoint.ex` — `import PhoenixVite.Plug` + a `:favicon`/vite-watcher plug
- `lib/new_api_app_web/router.ex` — `import Phoenix.LiveView.Router`, a `:browser` pipeline, an
  empty `scope "/"`
- `lib/new_api_app_web.ex` — `live_view/0`, `html/0`, `html_helpers/0` (standard
  Phoenix-generated web-module shape, wired to `CoreComponents`)

**`:contributes` entries**: `config/config.exs` (`key: :web_layer_config, at: :before_import`,
adds `config :live_svelte, ssr: false`), `config/dev.exs` (`key: :web_layer_dev`).

**New deps** (`mix.exs`): `{:phoenix_vite, "~> 0.5"}`, `{:phoenix_live_view, "~> 1.0"}`,
`{:live_svelte, "~> 0.18"}`.

**New aliases**: `assets.setup/build/deploy/check/lint/format/test/test.coverage/test.e2e`, all
`cmd --cd assets pnpm ...`; `setup` gains `"assets.setup"`.

No change to `application.ex`.

**Porting work required**: `priv/meta/web_component/` is derived against `baseline_api` the same
way every other component is, so it already carries the `new_api_app`/`NewApiApp` identity
capstone's convention expects (confirmed directly against svelixir's own
`priv/meta/web_component/mix.exs` — `app: :new_api_app`, `defmodule NewApiApp.MixProject`) — no
identity rewriting needed at port time. The `new_web_app`/`NewWebApp` identity appears only in
the *composed* `priv/meta/baseline_web` output, and only because `Compose`'s existing rename step
(`Template.capture/2`/`render/2`) is what produces it — already-implemented, already-tested
capstone machinery this work reuses unchanged, not something the port does by hand. Porting
`web_component/` itself is therefore a plain copy: no rename pass, only the hand-verification in
step 1 below.

## Building the plugin

Same sequence every other capstone plugin has used (grpc, cqrs, cache, openapi,
prod_image_api):

1. Copy svelixir's `priv/meta/web_component/` verbatim into capstone's `priv/meta/web_component/`
   (already `new_api_app`/`NewApiApp`-identified, no rename needed) and hand-verify it still
   compiles and its tests pass — the two projects' `baseline_api` trees may have drifted since
   they forked (different `generator_version`/Elixir/Phoenix pins), which could shift anchor text
   `derive` depends on.
2. Add `web_layer: %{derived_from: :api, path: "priv/meta/web_component"}` to
   `priv/baselines.exs`.
3. Run `mix capstone.plugin.derive web_layer` → produces
   `priv/meta/meta_web_layer/manifest.exs`. Re-running derive must reproduce the checked-in
   plugin byte for byte (same assertion every other plugin's derive test makes).
4. Add `web: %{derived_from: :api, plugin: :web_layer, path: "priv/meta/baseline_web"}` to
   `priv/baselines.exs`. This is the exact shape `test/mix/tasks/capstone.baseline.compose_test.exs`
   already exercises against a synthetic `probe` fixture — `web` is simply the first *real*
   entry to carry both `plugin:` and `derived_from:` together.
5. Run `mix capstone.baseline.compose web` → composes `api` + `meta_web_layer` into the
   checked-in `priv/meta/baseline_web/` tree, via capstone's existing
   `Mix.Tasks.Capstone.Baseline.Compose` (rename the source tree's identity via
   `Template.capture/2`/`render/2`, then `Capstone.Plugin.Apply.run/2` the plugin — already
   implemented, already tested against the `probe` fixture, unchanged by this work).
6. Run `mix capstone.baseline.record` to fill in `files`/`tree_digest`/`archive_sha256` for both
   new entries (same task every baseline already goes through).

## Testing

- **Derive round-trip**: re-deriving `web_layer` reproduces `priv/meta/meta_web_layer/`
  byte-for-byte — mirrors every existing `*_round_trip_test.exs` (`grpc_round_trip_test.exs`,
  `cqrs_round_trip_test.exs`, `round_trip_test.exs`). New file:
  `test/capstone/plugin/web_layer_round_trip_test.exs`.
- **Compose drift check**: an offline test (both inputs checked in, no generator needed —
  matching svelixir's `519baed`, which replaced a live `phx.new` toolchain test with exactly
  this) asserting `Compose.run(["web"])`'s output matches the checked-in `priv/meta/baseline_web`
  tree. Lives alongside the other baseline drift-check tests in `test/capstone/baseline_test.exs`.
- **Structural toolchain test**: a real `mix capstone.new` with a `target.exs` whose `base` is
  `:web`, then `mix compile` and `mix test` inside the generated project, `@tag :toolchain` —
  mirrors the existing `:grpc`/`:cqrs` structural toolchain tests. Because `assets.setup` shells
  out to `pnpm`, this test additionally needs `pnpm` on the toolchain machine — call this out
  explicitly in the test's own tag/skip message if `pnpm` isn't found, the same way the existing
  suite already gates `:toolchain` tests on `mix new`/`mix phx.new` being installed.
- **Options/Config unit tests** for the Phase B mechanism (below): `base: :web` and `base: :both`
  each produce `plugins: [:web_layer | ...]`; `base: :api` is unaffected; a `target.exs` that
  explicitly lists `:web_layer` alongside `base: :web` does not get it applied twice.

## Phase B: wiring `base: :web`/`:both` to `web_layer`

### The decision

**Revision note:** the first implementation of this section merged the implied plugin directly
into `Options.plugins` inside `from_config!/1`. That broke `Bootstrap.run/3`, which writes the
generated project's own `target.exs` via `Project.render_config(opts)` reading that SAME
`opts.plugins` — the implied `:web_layer` got baked back into `target.exs` as if the user had
typed it, contradicting this section's own stated goal below. Caught by Task 8's end-to-end
toolchain test, which is exactly what that test exists to prove. The corrected design (below) is
the one actually implemented.

`Options.plugins` keeps meaning exactly what it always meant, before this feature existed:
whatever `target.exs` (or a caller constructing `%Options{}` directly) explicitly declared —
untouched by `base:`. Merging in the implied plugin happens as a separate, pure, on-demand
computation, read only by the one consumer that actually needs the merged list
(`Capstone.New.Bootstrap.apply_plugins!/3`, which installs plugins) — never by the consumer that
needs the untouched, declared-only list (`Capstone.New.Project.render_config/1`, which writes
`target.exs`). One field, two different readers with two different needs, is what broke; two pure
functions reading the same field for two different purposes is what doesn't.

```elixir
@base_plugins %{web: [:web_layer], both: [:web_layer]}

@doc """
Plugins a base implies, in addition to whatever `target.exs` lists explicitly.

`:api` implies nothing — it is the bare tree every other base is generated from
and derived against. `:web` and `:both` both imply `:web_layer`: the LiveView/
Svelte layer never comes from the generator (`generator_argv/1` strips
`--no-html --no-assets` for all three phx.new-driven bases identically), only
from this plugin being applied, exactly as `generator_argv/1`'s own moduledoc
already documents.
"""
@spec implied_plugins(base()) :: [atom()]
def implied_plugins(base), do: Map.get(@base_plugins, base, [])

@doc """
Every plugin that should actually be installed: base-implied plugins plus whatever
was explicitly declared, deduplicated. This is the ONLY place the two lists merge —
`plugins:` itself (declared-only) is never mutated, so `target.exs` (written from
`plugins:`, never from this) stays an honest record of what the user asked for.
"""
@spec effective_plugins(t()) :: [atom()]
def effective_plugins(%__MODULE__{} = opts) do
  (implied_plugins(opts.base) ++ opts.plugins) |> Enum.uniq()
end
```

`from_config!/1` is **unchanged** by this feature — it still does the plain `plugins:
config.plugins` passthrough it always did. `Options.plugins` therefore never differs, for any
caller, from whatever was explicitly requested — via `target.exs`, or via a direct `%Options{}}`
construction in a test — with zero change to any existing construction site.

`Capstone.New.Bootstrap.apply_plugins!/3` (`lib/capstone/new/bootstrap.ex`) is the one place that
changes: it installs `Options.effective_plugins(opts)` instead of `opts.plugins`. This is the only
consumer that ever needs the merged list — every other consumer (`Project.render_config/1`
included) keeps reading `opts.plugins` and is correctly unaware `:web_layer` arrived by
implication rather than by explicit listing.

Ordering inside `effective_plugins/1`: implied plugins first, so an explicit entry later in
`opts.plugins` naming the same plugin is what `Enum.uniq/1` keeps the position of — irrelevant for
`Capstone.Plugin.Install` today (nothing currently orders plugin application by list position, per
`Capstone.Manifest`'s own "encode!/1 sorts plugins by name" ordering rule), called out here only
so a future ordering dependency has an explicit rule to change rather than an accidental one to
discover.

### Why not the alternatives

- **Merging into `Options.plugins` inside `from_config!/1`** (the first attempt) is exactly the
  bug this revision fixes — see the revision note above. A single field cannot honestly serve a
  reader that wants "what was declared" and a reader that wants "what should be installed" once
  those two answers can differ.
- **A `Bootstrap`-level ad-hoc conditional** (`if opts.base in [:web, :both], do: Install.run(...)`
  inlined directly, with no named function) duplicates the base→plugin mapping as a one-off
  branch rather than a single named, testable function, and — because generation and update are
  different entry points that both need this behavior — risks the special-case being written once
  and forgotten in the other. `effective_plugins/1` avoids this: it is a plain, exported, unit-
  tested function on `Options`, and `Bootstrap` merely calls it — the DRY property this bullet
  argues for is preserved, just computed on demand instead of stored.
- **Reading the mapping out of `priv/baselines.exs` at runtime** keeps `lib/` as the single
  source of truth in theory, but `priv/baselines.exs`/`priv/meta/` are maintainer-only artifacts
  absent from what an end user's `{:capstone, "~> 0.x", only: :dev}` hex install actually
  contains — this option is not available to code that must run inside a consumer's project.

### `:both`

Treated identically to `:web` for this work: both imply `[:web_layer]`. Nothing today
distinguishes `:web` from `:both` beyond this — both already produce the identical stock tree at
generation time (`Options.generator_argv/1`), and until a second base-implying plugin exists,
there is nothing for `:both` to carry that `:web` doesn't. If a future plugin needs to
distinguish them, `@base_plugins` is the one place that changes.

## Publishing

After the plugin is built, derived, composed, and tested locally: run
`mix capstone.baseline.record` (already covers `web_layer`/`web` once step 6 above has run;
listed again here as the trigger for cutting a release, not a new task) to produce the
versioned archives, then cut and push an actual GitHub release with those archives attached, the
same way `api`/`cache`/`cqrs`/`grpc`/`openapi`/`prod_image_api` already are. This is an external,
hard-to-reverse, publicly-visible action — the implementation plan must treat it as its own
explicit confirmation step at the time, not something that happens automatically once the rest of
the work is green.

## Out of scope

- Any actual application/domain code built with the shipped LiveView/Svelte scaffolding — this
  plugin ships infrastructure only, matching every other plugin's convention (a worked example
  belongs in the README, not the plugin tree).
- Changing `Options.generator_argv/1`'s stock-tree generation itself. It continues to strip
  `--no-html --no-assets` identically for `:api`/`:web`/`:both` — that is what makes deriving
  `web_layer` against a bare `api` tree possible in the first place, and this spec does not
  revisit that decision.
- A capability/plugin-conflict solver (goals.md D17/G9's "capability solver," explicitly
  deferred there) — `web_layer`'s composability with the other existing plugins (`:cache`,
  `:cqrs`, `:grpc`, `:openapi`) is not verified by this work beyond "each derives cleanly against
  `:api` independently"; a project combining `:web_layer` with another plugin is not exercised by
  the tests this spec adds.
- Upgrading `priv/meta/baseline_api`'s own Elixir/Phoenix/generator pins. If step 1's
  hand-verification finds the ported tree doesn't compile cleanly against capstone's current
  `baseline_api` because of drift since the svelixir fork, the fix is adapting `web_component` to
  capstone's current baseline — not bumping the baseline to match svelixir's.

## Verification notes (empirical checks the implementation plan must re-confirm)

Unlike the `:grpc` spec, the deps/versions here were not independently re-verified against
current Hex source during spec-writing — they were read off svelixir's already-working,
already-tested tree, which is good provenance but not the same as checking today's Hex. Before
treating any of the following as final, the implementation plan must confirm:

- `{:phoenix_vite, "~> 0.5"}`, `{:phoenix_live_view, "~> 1.0"}`, `{:live_svelte, "~> 0.18"}` are
  still current, and are compatible with whatever Phoenix version capstone's *current*
  `priv/meta/baseline_api` actually pins (`generator_version: "1.8.9"` as of this writing) —
  svelixir's fork point may have pinned a different Phoenix version.
- What `sv5ui` actually is: the investigation found `assets/svelte/lib/sv5ui.js` as a file inside
  the ported tree, not confirmed as a published npm package svelixir's `package.json` depends on.
  Confirm during porting whether it's local project code (ports as-is) or an external dependency
  (needs a pinned version in `assets/package.json`/`pnpm-lock.yaml`).
- Whether `priv/meta/baseline_api`'s tree has diverged between svelixir and capstone since the
  fork (different `generator_version`, different already-applied fixes) enough to break the
  anchor text `web_component`'s `:manual` hunks (`endpoint.ex`, `router.ex`, `new_api_app_web.ex`)
  depend on. If anchors don't match, they need re-anchoring against capstone's actual current
  `baseline_api`, not svelixir's.
- Whether `pnpm` needs to be added to the CI toolchain image for the new `:toolchain`-tagged
  structural test to run in CI at all (mirroring however `protoc`/`phx_new` availability is
  currently handled for the other toolchain-gated tests).
