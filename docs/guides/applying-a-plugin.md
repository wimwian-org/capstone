# Applying a plugin

This guide covers how a plugin's files actually land in a project — whether
that's during `mix capstone.new`, via the low-level `mix capstone.plugin.apply`
task, or (for an existing project) via `mix capstone.update`, covered in
[Upgrading the installation](upgrading-the-installation.md).

If you're writing a plugin rather than using one, see
[Building a plugin](building-a-plugin.md).

## The common case: declare it in `target.exs`

Most projects never call an apply task directly. `target.exs` — the small
Elixir literal `mix capstone.new` reads — has a `plugins:` key:

```elixir
%{
  schema_version: 1,
  base: :api,
  project: [name: "my_app", github_org: "acme"],
  plugins: [:cache, :openapi]
}
```

`plugins` is a list of plugin-type atoms. During `mix capstone.new`, each
one is resolved against the registry shipped inside the `capstone` package
and applied — in order, before `mix deps.get`/`mix deps.compile` run, so
that a plugin's declared dependencies are actually fetched.

## What "applying" actually does

Whether triggered by `mix capstone.new` or `mix capstone.update`, applying
one plugin is always the same five-step sequence
(`Capstone.Plugin.Install.run/3`):

1. **Resolve** — `Capstone.Plugin.Registry.resolve!/4` picks the one
   archive matching the requested type, the running Elixir version (major.minor
   only — patch doesn't matter), and the highest capstone version not
   exceeding this build's own. A tie between two archives at the same
   capstone version is broken by the highest content hash — deterministic,
   not "whichever sorts first on this filesystem."
2. **Extract** — the resolved `.tar.gz` is unpacked into a temporary
   directory (`:erl_tar`, which validates every entry path and symlink
   target against escaping the extraction root).
3. **Apply** — `Capstone.Plugin.Apply.run/3` writes each file per its
   ownership mode (see [Building a plugin](building-a-plugin.md#files1--what-the-plugin-writes)
   for what `:sole_owner`, `:contributes`, `:seed` and `:manual` each do),
   and splices the plugin's declared `deps:` into the target's `mix.exs`.
4. **Record** — if the target has a `target.exs` (i.e. it's a Capstone
   project), an entry is appended to its `plugin.exs`: the plugin's name,
   version, origin, applied-at timestamp, and the content hash of every file
   it wrote. A target with no `target.exs` is installed all the same, but
   nothing is recorded — there's no file to make it updatable later.
5. **Clean up** — the temporary extraction directory is removed.

Every step either succeeds completely or raises. There's no partial-apply
state to reason about.

## The low-level task: `mix capstone.plugin.apply`

For applying a *derived* plugin (one sitting in `priv/meta/meta_<name>/`,
not yet packaged into the registry) directly to a target directory — useful
while developing a plugin, before it's ready to package:

```bash
mix capstone.plugin.apply cache ../my_app
```

This skips resolve/extract entirely and applies straight from the derived
directory. Run `mix capstone.check` against the target afterward — an entry
whose `:manual` anchor couldn't be located lands as a conflict region that
won't compile until a human moves it, and this is the only step that
catches that before it ships.

```bash
mix capstone.check ../my_app
```

reports every unresolved conflict marker still in the tree. Clean output
means nothing needs hand-resolving; a non-empty list names the file and the
plugin key that left it.

## Resolving what's actually installed

`plugin.exs` — recorded automatically for any project with a `target.exs`
— is the durable record of what was applied and when:

```elixir
%{
  schema_version: 2,
  base: :api,
  plugins: [
    %{
      name: :cache,
      version: "0.1.0",
      origin: {:registry, "cache-1.20.3-0.1.0-b6a0deac69a3.tar.gz"},
      applied_at: "2026-08-27T06:00:00Z",
      files: [
        %{path: "lib/my_app/cache.ex", mode: :sole_owner, hash: "sha256:..."}
      ]
    }
  ],
  config_digest: "sha256:...",
  generated_at: "2026-08-27T05:00:00Z",
  capstone_version: "0.10.0"
}
```

`Capstone.Manifest.read!/1` reads this back — completely independently of
the target's `mix.exs`, its deps, or `_build`, and without Mix even being
started. That's deliberate: `mix capstone.update` has to run against a
project that may not currently compile.

## Retiring an archive

If a plugin archive turns out to be wrong — mismatched anchors, a stale
baseline, a security regression — it's **retired**, never deleted:

```bash
mix capstone.plugin.retire cache-1.20.3-0.1.0-b6a0deac69a3.tar.gz
```

The file stays on disk (for provenance — anything that already resolved to
it keeps working), but future calls to `Capstone.Plugin.Registry.resolve!/4`
skip it entirely. There's no un-retire; ship a corrected archive under a new
content hash instead.

## See also

- [Building a plugin](building-a-plugin.md) — the `Capstone.Plugin.Behavior`
  contract and how a first-party plugin is derived and packaged.
- [Upgrading the installation](upgrading-the-installation.md) — applying a
  plugin to a project that was already generated.
