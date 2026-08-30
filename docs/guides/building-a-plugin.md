# Building a plugin

A Capstone plugin installs one infrastructure concern into a generated
project — a cache, a container runtime, a vault, an auth stack — and knows
nothing about what the project is for. This guide covers both ways to build
one: implementing the public `Capstone.Plugin.Behavior` contract directly,
and deriving a first-party plugin from a raw working project the way this
repository builds `cache`, `openapi` and `prod_image_api`.

If you only want to *use* an existing plugin, see
[Applying a plugin](applying-a-plugin.md) instead.

## The contract: `Capstone.Plugin.Behavior`

This is the stable, public API. It's meant to be implemented in a module
that lives in its own repository — a plugin never needs to edit Capstone's
source to exist.

```elixir
defmodule MyOrg.Valkey do
  use Capstone.Plugin.Behavior, name: :valkey, version: "1.3.0"

  @impl true
  def files(_config) do
    [
      {"lib/APP/cache.ex", :sole_owner},
      {"compose.yaml", :contributes, key: :valkey_service}
    ]
  end

  @impl true
  def deps, do: [{:nebulex, "~> 3.0"}]

  @impl true
  def requires, do: [:container_runtime]
end
```

`use Capstone.Plugin.Behavior, name: ..., version: ...` validates both
options at compile time — a plugin with a malformed name or a non-semver
version fails to build, rather than failing when a project tries to install
it — and supplies overridable defaults (`[]`) for `deps/0`, `requires/0`,
`provides/0` and `conflicts/0`. Only `files/1` must be implemented.

### `files/1` — what the plugin writes

The heart of a plugin is data, not code: a list of `{path, mode}` or
`{path, mode, opts}` entries, one per file the plugin touches. `path` uses
`APP` as a placeholder for the target project's own app name
(`Capstone.Template` substitutes it at apply time). The mode is one of:

- **`:sole_owner`** — the plugin owns this file outright; nothing else may
  claim it.
- **`:contributes`** — the plugin adds one block to a file others also
  contribute to. Requires `key: :some_atom` to identify the block.
- **`:seed`** — written once at generation and never touched again on a
  later apply.
- **`:manual`** — a hunk that can't be appended safely (an existing file's
  interior, not its end). Requires `key:` and an `after:` anchor — the exact
  lines the new content is spliced after. If the anchor text isn't found in
  the target file, the entry falls back to an unresolved conflict region
  that **will not compile** until a human resolves it (`mix capstone.check`
  is what catches this before it ships).

```elixir
def files(_config) do
  [
    {"lib/APP/cache.ex", :sole_owner},
    {"README.md", :contributes, key: :cache_readme},
    {"lib/APP.ex", :manual, [after: ["      :world", "", "  \"\"\""], key: :cache_app]}
  ]
end
```

A `:manual` anchor is fragile by nature — it's matched against literal text
in the target's baseline. **Verify the anchor text actually exists in every
base your plugin claims to support** before shipping it; a mismatch doesn't
fail loudly at packaging time, it fails quietly by leaving a broken file in
every project that applies the plugin.

### `deps/0` — dependencies, declared

```elixir
def deps, do: [{:nebulex, "~> 2.6"}]
```

This is a **declared** list, not something read back out of the plugin's own
`mix.exs`. A plugin that reflects its own project's dependency list risks
copying `in_umbrella: true` or path deps straight into the target project
and breaking it. Say exactly what the target needs.

### `requires/0`, `provides/0`, `conflicts/0` — capabilities

Named atoms used to resolve plugin ordering and conflicts — e.g. a cache
plugin might `provide: [:cache]`, and a plugin that needs a running cache
would `require: [:cache]`. All three default to `[]`.

### `transform/2` and `upgrade/3` — the two escape hatches

For the rare case the file list can't express: `transform(root, config)`
runs at install time for anything beyond writing files; `upgrade(root,
from_version, to_version)` migrates an already-installed copy of the plugin
between versions (see [Upgrading the installation](upgrading-the-installation.md)
for why this is currently unreachable — `mix capstone.update` never
re-resolves an already-recorded plugin, so `upgrade/3` has no caller yet).

**Both callbacks must let exceptions propagate.** Never wrap the body in a
bare `rescue`. A transform that silently swallows a failure and returns
`:ok` anyway gets recorded in `plugin.exs` as having succeeded — the
manifest becomes a claim instead of a fact, and nothing downstream can tell
the difference between "this worked" and "this pretended to."

### Determinism

Everything a plugin returns must be a pure function of its inputs — the
same `config` must produce the same bytes today and in eighteen months. No
timestamps, no randomness, no relying on map iteration order. `mix
capstone.plugin.package` content-addresses the resulting archive by its
tarball's hash; a plugin that isn't deterministic breaks that addressing
scheme, and an `upgrade/3` that diffs a historical version against a
regenerated one depends on the regeneration being exact.

## Deriving a first-party plugin

If you're adding a plugin to *this* repository's own shipped registry
(`priv/plugins/`) rather than distributing one standalone, the path is
different: derive it from a real, compiling project rather than
hand-writing a `Behavior` implementation.

### 1. Register the raw project in `priv/baselines.exs`

A raw project is a real Elixir project you can `cd` into and run — no
placeholders. Register it with:

```elixir
my_plugin_component: %{
  path: "priv/meta/my_plugin_component",
  derived_from: :api,   # which generatable base this plugin's anchors assume
  names: %{app: "new_api_app", module: "NewApiApp", name: "new_api_app"}
}
```

`derived_from` matters more than it looks: it's the baseline your `:manual`
anchors (if any) must exist in. `mix capstone.new` can only generate `:api`,
`:web` and `:both` projects — there's no `:otp` value in `target.exs`'s own
schema — so a plugin derived against an `:otp`-only baseline can never be
cleanly applied to anything the generator actually produces. Check this
*before* deriving, not after.

### 2. Derive it

```bash
mix capstone.plugin.derive my_plugin
```

This reads the raw project at the registered `path`, captures it against
its own `names` (via `Capstone.Template.capture/2`), and writes the
name-agnostic, `APP`-placeholder'd result to `priv/meta/meta_my_plugin/`,
along with a generated `manifest.exs` describing every file and its
ownership mode.

A directory whose name starts with `meta_` carries placeholders; one that
doesn't is a raw project — `my_plugin_component` in, `meta_my_plugin` out.

If the raw project *deletes* a baseline file relative to what it derived
from, this fails: SDD 7.3 has no ownership mode for a deletion, so it must
be represented some other way (or the deletion avoided).

A raw project whose own `compose.yaml` bind-mounts a runtime data directory
(e.g. `valkey_component`'s `.valkey_data/`) needs that directory deleted
before you touch it here — being gitignored is not enough, since every path
below walks the filesystem, not the git index. Left in place, a binary
snapshot file in that directory breaks `derive` (`Capstone.Plugin.Derive`
tries to template it as text and raises), the round-trip test for that
plugin (it walks the raw project directly), `mix capstone.baseline.record`,
and `test/capstone/baseline_test.exs`'s drift check — all four read the raw
tree the same way. `rm -rf` the directory (or stop the sidecar first) before
running any of `derive`, `baseline.record`, or the test suite.

### 3. Package it

```bash
mix capstone.plugin.package my_plugin
```

Reads `priv/meta/meta_my_plugin/`, builds a deterministic `.tar.gz` (mtime,
uid and gid all zeroed; entries sorted by path; hashed pre-gzip so the
archive filename doesn't depend on gzip's own embedded timestamp), and
writes it to `priv/plugins/<type>-<elixir>-<capstone>-<sha>.tar.gz`.

`<name>` must already be a key of `priv/baselines.exs` — the same manifest
`derive` reads.

### 4. Verify it resolves and applies

```bash
mix run -e 'IO.inspect(Capstone.Plugin.Registry.resolve!(:my_plugin, System.version(), Capstone.MixProject.project()[:version], Capstone.Plugin.Registry.default_dir()))'
```

Then generate a real test project with `plugins: [:my_plugin]` in its
`target.exs` and confirm it actually **compiles** — not just that the
expected files exist. A `:manual` entry whose anchor doesn't match leaves
broken code behind while still reporting success; `mix capstone.check` run
inside the generated project is what catches an unresolved conflict region
before it ships.

## Deriving from an existing plugin (composing a variant)

Some bases are themselves derived rather than generated — `priv/baselines.exs`
records `:web` as `derived_from: :api` plus a plugin, not as its own
downloaded tree. `mix capstone.baseline.compose <name>` builds that kind of
derived baseline: rename the source tree to the target's names, then apply
the plugin on top. This is a maintainer-only tool for building the
baselines other plugins derive against — see its moduledoc if you're adding
a new derived base rather than a new plugin.

## See also

- [Applying a plugin](applying-a-plugin.md) — how a project actually gets a
  plugin's files, whether via `mix capstone.new`, `mix capstone.update`, or
  the low-level `mix capstone.plugin.apply`.
- [Upgrading the installation](upgrading-the-installation.md) — adding a
  plugin to a project that already exists.
