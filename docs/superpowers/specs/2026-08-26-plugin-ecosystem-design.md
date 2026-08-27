# Plugin ecosystem: cradle to grave — design

Date: 2026-08-26
Status: approved, pending implementation plan

## Purpose

Capstone's plugin machinery today stops halfway. `mix capstone.plugin.derive`
and `mix capstone.plugin.apply` exist, but they are maintainer-only tools that
read and write bare directories under `priv/meta/`, resolved relative to the
current working directory — they only work run from inside a checkout of this
repository, never from `deps/capstone` inside a project someone generated.
`Capstone.Config` enforces this boundary explicitly: `plugins:` in
`target.exs` validates only against the literal `[]` (goals.md decision D17 —
"no feature plugins ship in the MVP").

This spec builds the rest of the lifecycle goals.md already commits to but
doesn't implement: a plugin becomes a versioned, content-addressed artifact
that ships inside the `capstone` package itself, a project can name one by
type in its own `target.exs`, and both `mix capstone.new` (fresh generation)
and a new `mix capstone.update` (an existing project) resolve and apply it.
Retirement — marking an artifact as no longer offered to new resolutions,
without deleting it — is the "grave" end of the lifecycle.

## Naming

A packaged plugin is a gzipped tar named:

```
<type>-<elixir-version>-<capstone-version>-<sha>.tar.gz
```

Hyphen-delimited, four segments, e.g.:

```
cache-1.20.3-0.1.0-a3f9c21b0e77.tar.gz
openapi-1.20.3-0.2.0-7b1e40d9aa02.tar.gz
prod_image_api-1.20.3-0.1.4-0c88ff21ab55.tar.gz
```

- **type** — the plugin's name, `[a-z][a-z0-9_]*`, matching an entry key in
  `priv/baselines.exs` the same way it does today.
- **elixir-version** — the exact `System.version()` of the Elixir that ran
  `mix capstone.plugin.package` to build this archive, e.g. `1.20.3`.
- **capstone-version** — the exact `capstone` version (`Application.spec/2`,
  the same source `Capstone.Plugin.Record` already uses) that ran the
  packaging step.
- **sha** — the first 12 hex characters of a SHA-256 over the archive's own
  deterministic tar bytes (defined in [Packaging](#packaging) below) — a
  content hash, not a git commit SHA. Same content packaged twice produces the
  same sha; any change to the plugin's files or manifest changes it.

All four segments are re-derivable from the archive's own content and build
environment; nothing here is hand-assigned.

This assumes `System.version()` and the `capstone` version are both plain
`x.y.z` releases, never a pre-release tag (`1.20.3-rc.0`) — a hyphen inside
either segment would break the 4-way split in [Resolution](#resolution). Both
are true for every Elixir and every `capstone` release today; if that ever
changes, the parser needs to anchor on `type` (which never contains a hyphen)
and the trailing `-<sha>.tar.gz`, and read the two version segments as
whatever's left between them, rather than a blind 4-way split.

## Storage

Packaged archives live in `priv/plugins/`, checked into git alongside
`priv/baselines.exs`:

```
priv/plugins/
  cache-1.20.3-0.1.0-a3f9c21b0e77.tar.gz
  cache-1.20.3-0.1.4-7b1e40d9aa02.tar.gz
  openapi-1.20.3-0.2.0-0c88ff21ab55.tar.gz
  retired.exs
```

`retired.exs` is a literal list of retired filenames, read the same way
`plugin.exs`/`target.exs` are — parsed, never evaluated:

```elixir
["cache-1.20.3-0.1.0-a3f9c21b0e77.tar.gz"]
```

Retiring never deletes the archive: it stays on disk for provenance (an
already-applied project's `plugin.exs` still names it by filename) and is
simply excluded from future resolution.

### `priv/plugins/` ships in the package; `priv/meta/` and `priv/baselines.exs`
### still don't

This is the one point this spec resolves that wasn't a direct answer to a
brainstorming question, because it follows necessarily from "full
integration" rather than being a preference: `mix capstone.new` and
`mix capstone.update` run inside a project that depends on `capstone` (or
under a globally-installed `capstone` archive), never inside this repository's
own checkout. For them to resolve a plugin at all, `priv/plugins/` has to be
reachable from wherever `capstone` itself is installed — so, unlike
`priv/meta/` and `priv/baselines.exs` (which stay maintainer-only, absent from
`package.files`, and resolved as bare CWD-relative paths by the derive/apply
tasks), `priv/plugins/` is:

- added to `package.files` in `mix.exs`, so it ships in both the hex package
  and the `.ez` archive (a Mix archive packages its own `priv/` alongside its
  `ebin/` — verified when the original capstone/capstone_new split spec probed
  archive behavior; only a dependency's *dependencies* fail to bundle, an
  app's own `priv/` always ships).
- resolved at runtime via `Application.app_dir(:capstone, "priv/plugins")`,
  never a bare `"priv/plugins"` string — the same directory whether `capstone`
  is loaded from `deps/capstone` or from a globally-installed archive.

One consequence worth stating plainly: because the registry ships inside the
package, retiring an archive or adding a newly-packaged one only takes effect
for whoever is running a `capstone` version built *after* that change —
there is no separately-updatable, out-of-band registry. That is an accepted
trade-off, not an oversight: it keeps the "no external dependencies, no
network calls" property the rest of `capstone` already holds (see
`CredoNoRuntimeDepsTest`), at the cost of a retirement or a new plugin version
only reaching consumers on their next `capstone` bump.

## Packaging

`mix capstone.plugin.package <name>` (`Capstone.Plugin.Package`) reads
`priv/meta/meta_<name>/` — the directory `mix capstone.plugin.derive <name>`
already produces, unchanged — and:

1. Walks the tree, collecting every file's relative path and raw bytes,
   `manifest.exs` included.
2. Sorts entries by path (byte order), builds a tar with every entry's mtime,
   uid, and gid zeroed — the same "make it reproducible" discipline
   `Capstone.Hash` and the vendor-digest check already apply elsewhere in this
   codebase. Two packaging runs over identical derived content produce
   byte-identical tars.
3. Gzips the tar, then takes `SHA-256` over the **un-gzipped, deterministic
   tar's bytes** (gzip's own header carries a timestamp; hashing before gzip
   keeps the sha stable across otherwise-identical runs), truncated to the
   first 12 hex characters.
4. Names the file `<name>-<System.version()>-<capstone version>-<sha>.tar.gz`
   and writes it to `priv/plugins/`.

This sha is a plain content hash — not `Capstone.Hash.content_hash/2`, whose
comment-insensitive normalization exists for drift detection against a
human-edited target file. A package's identity has to reflect the exact bytes
being shipped, so a comment change in a plugin's own source **does** produce a
new archive.

`derive` and `package` stay two separate tasks: `derive`'s loose-directory
output remains inspectable and reviewable before anyone commits to shipping
it (the review value goals.md already assigns manifest-only plugins under
D20), and `derive`'s existing tests and contract (`priv/meta/meta_<name>/`,
`wrote #{out}/manifest.exs`) are untouched by this spec.

## Resolution

`Capstone.Plugin.Registry.resolve!(type, elixir_version, capstone_version)`:

1. List `priv/plugins/*.tar.gz` (via `Application.app_dir(:capstone,
   "priv/plugins")`, see above), parsing each filename into
   `{type, elixir, capstone, sha}`. A filename that doesn't parse into exactly
   four hyphen-delimited segments plus `.tar.gz` is skipped with a
   `Mix.shell().info/1` warning, never raised — one stray file must not break
   every resolution.
2. Filter to entries whose `type` matches the requested type.
3. Filter to entries whose `elixir` shares **major.minor** with
   `elixir_version` (a `1.20.3` target accepts a `1.20.0`-built archive,
   rejects `1.19.x` and `1.21.x`).
4. Drop any entry whose filename is listed in `retired.exs`.
5. Drop any entry whose `capstone` segment is a semver **greater than**
   `capstone_version` — an older running `capstone` must never apply an
   archive stamped by a newer one it might not understand.
6. Of what survives, pick the entry with the highest `capstone` segment.
   Ties (two entries with the same capstone segment — only possible if their
   shas also differ, since identical content produces an identical name) are
   broken by highest sha, purely so `resolve!/3` is a pure, deterministic
   function of `{type, elixir_version, capstone_version}` and the directory
   listing — never dependent on filesystem enumeration order.
7. No candidates survive at any step → `Mix.raise/1`, naming the type and the
   Elixir/Capstone versions that eliminated every candidate, so the failure
   names what to fix rather than just "not found."

`elixir_version` and `capstone_version` are passed in by the caller
(`Capstone.New.Bootstrap` reads `System.version()` and
`Application.spec(:capstone, :vsn)`, the same sources `Capstone.Plugin.Record`
already uses) — `resolve!/3` itself takes no ambient reading, for the same
injected-seam-for-testability reason every other `Capstone.*` module in this
codebase does.

## `Capstone.Config` and `target.exs`

`plugins:` moves from "must equal `[]`" to "a list of atoms, each an existing,
resolvable plugin type": `plugins: [:cache]`. Validation checks each entry is
an atom; it deliberately does **not** check the type resolves to an actual
archive at `Config` decode time — `Config.read!/1` is used by code paths that
have no reason to touch the plugin registry (`Capstone.Plugin.Record`'s own
`config_digest` computation, for one), and a config file should describe
intent, not a live query against installed archives. Resolution failure
surfaces at apply time, from `Capstone.Plugin.Registry.resolve!/3`, with the
name-what-to-fix error `resolve!/3` already produces.

This is a schema change to an already-shipped struct, so it is a **relaxation
of a `{:invalid_value, ...}` error**, not a breaking change to anything that
currently validates — every `target.exs` that was valid before (`plugins: []`)
stays valid.

## Application

### `mix capstone.new`

`Capstone.New.Bootstrap`'s sequence gains one step, ordered last (after
`target.exs` is written, matching how `Capstone.Plugin.Record` already
requires a `target.exs` to exist before it will write anything): for each atom
in the freshly-written `target.exs`'s `plugins:`, in list order —

1. `Capstone.Plugin.Registry.resolve!(type, elixir_version, capstone_version)`
2. Extract the resolved archive to a fresh directory under
   `System.tmp_dir!/0`
3. `Capstone.Plugin.Apply.run/2` against that directory and the generated
   project
4. `Capstone.Plugin.Record.run/4` to record it in the generated project's
   `plugin.exs`
5. Remove the temp directory

Any failure at any step — resolution or apply — raises `Mix.Error` and aborts
the whole `mix capstone.new` invocation. A generated project is never left
half-plugged: this mirrors D9/G9's order-independent-composition guarantee by
refusing to produce a project whose plugin set doesn't match what
`target.exs` declared.

### `mix capstone.update` (new)

```
mix capstone.update [target]
```

`target` defaults to the current working directory. `Capstone.Update`:

1. Reads `target`'s `target.exs` for its current `plugins:` list.
2. Reads `target`'s `plugin.exs`, if present, for the set of already-recorded
   plugin names (`Enum.map(manifest.plugins, & &1.name)`); an absent
   `plugin.exs` is treated as an empty set.
3. Computes `newly_listed = plugins -- already_recorded` (as a `MapSet`
   difference, so order in `target.exs` doesn't matter and duplicates collapse).
4. For each type in `newly_listed`, runs the exact same
   resolve → extract → apply → record → cleanup sequence `capstone.new` uses.

**Explicitly out of scope**, matching the boundary
`Capstone.Plugin.Record`'s own moduledoc already documents as unwritten (its
"D7's work" note): `capstone.update` never touches a plugin that is already
recorded, even if a newer matching archive now resolves for that type. There
is no upgrade-in-place here — only "apply what's newly declared and wasn't
there before." Removing a plugin from `target.exs` is likewise not handled;
`plugin.exs` is additive-only in this spec, same as it is today.

## `plugin.exs` schema (v3)

`Manifest.Plugin` gains one field: `archive :: String.t() | nil` — the exact
resolved filename that was applied, e.g.
`"cache-1.20.3-0.1.0-a3f9c21b0e77.tar.gz"`. `nil` covers the existing
manual/directory-based `mix capstone.plugin.apply` path, which has no registry
archive to name.

Schema bumps from 2 to 3, following the 1→2 precedent already in
`Capstone.Manifest`: `@schema_versions [1, 2, 3]`, `@schema_version 3`.
Decoding accepts all three; encoding always writes 3; `archive` reads back
`nil` for any `Manifest.Plugin` entry that predates this field. No other field
changes.

## What stays untouched

- `Capstone.Plugin.Derive`, `Capstone.Plugin.Apply`, `Capstone.Baseline`, and
  every existing `capstone.baseline.*` / `capstone.plugin.derive` /
  `capstone.plugin.apply` task keep their current contracts, inputs, and
  tests exactly as they are. This spec adds a layer in front of `Apply`
  (extract-then-apply), never changes `Apply` itself.
- `priv/meta/` and `priv/baselines.exs` stay maintainer-only, CWD-relative,
  and absent from `package.files` — nothing here changes their resolution or
  their exclusion from what ships.
- Retiring a plugin never deletes its archive.

## Testing

Following this codebase's existing conventions throughout — ExMachina
factories for fixtures, `Capstone.Plugin.RegistryTest` covering every branch
of `resolve!/3` (type miss, major.minor miss, all-candidates-retired,
capstone-too-new, the tie-break rule), a round-trip test for
`Capstone.Plugin.Package` (derive → package → unpack → bytes match,
mirroring the existing `test/capstone/plugin/round_trip_test.exs` pattern),
and integration coverage for both `mix capstone.new` and `mix capstone.update`
against the real generator, in the style
`test/integration/target_project_test.exs` already establishes rather than
against a faked one. The existing gates — 100% line coverage, `mix credo
--strict`, `Capstone.BoundaryGuard`, `CredoNoRuntimeDepsTest`, `mix dialyzer`,
`mix doctor` — apply to every new module and task exactly as they do to
everything already in this repository.

## Explicit scope decisions

- **No network fetch, no third-party plugin sources.** Every archive ships
  inside the `capstone` package itself. goals.md's G7 ("third parties are
  first class") is a stated future goal this spec does not implement —
  nothing here forecloses it (a later spec could add a fetch behaviour ahead
  of `Application.app_dir`-only resolution), but building it now was
  explicitly declined during brainstorming in favor of the simpler
  local-registry approach.
- **No plugin removal / uninstall.** Only creation, storage, and (additive)
  application are in scope, plus registry-side retirement. Reversing an
  applied plugin's files out of a target project is not built here.
- **No upgrade-in-place.** `mix capstone.update` only applies plugins newly
  named in `target.exs`; it never re-resolves or replaces an already-recorded
  plugin even when a better-matching archive exists.
