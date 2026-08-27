# Upgrading the installation

`mix capstone.update` applies whatever plugins a project's `target.exs`
newly lists that its `plugin.exs` hasn't recorded yet. It's how an existing,
already-generated project picks up a plugin added after the fact — without
regenerating anything.

If you're looking for how a plugin's files get written in the first place,
see [Applying a plugin](applying-a-plugin.md). If you're building a plugin,
see [Building a plugin](building-a-plugin.md).

## The common case

Add the new plugin type to the project's `target.exs`:

```diff
 %{
   schema_version: 1,
   base: :api,
   project: [name: "my_app", github_org: "acme"],
-  plugins: [:cache]
+  plugins: [:cache, :openapi]
 }
```

Then, from inside the project:

```bash
mix capstone.update
```

This compares `target.exs`'s `plugins:` list against what's already
recorded in `plugin.exs`, applies only the types that are newly listed
(`:openapi`, in the example above — `:cache` is already recorded and is left
completely alone), and prints what it did:

```
applied: openapi
```

or, if there's nothing new:

```
nothing new to apply
```

`mix capstone.update [TARGET]` also accepts an explicit path, defaulting to
the current directory — useful for updating a project you're not currently
inside:

```bash
mix capstone.update ../my_app
```

## What "upgrading" does *not* mean

This is the one thing worth being precise about: `mix capstone.update`
**never re-resolves or replaces an already-recorded plugin**, even if a
newer, better-matching archive now exists for it. There is no
upgrade-in-place. Only "apply what's newly declared and wasn't there
before."

Concretely:

- Bumping a plugin's version in the registry does nothing for a project
  that already has that plugin type applied — `plugin.exs` already has an
  entry for it, so `mix capstone.update` skips it.
- Removing a plugin from `target.exs`'s `plugins:` list does nothing
  either. `plugin.exs` is additive-only; there's no "uninstall."
- Hand-editing a file a plugin wrote and then running `mix capstone.update`
  is safe — the edit is left completely untouched, since the plugin that
  wrote it is already recorded and is never touched again.

This is a deliberate, explicit scope boundary, not an oversight. If your
mental model is "keep re-running update to pull in the latest version of
everything," that's not what this does — it's closer to "apply the plugins
I haven't installed yet."

## After running it

A plugin's `deps:` are spliced into the target's `mix.exs`, but
`mix capstone.update` does **not** run `mix deps.get` afterward the way
`mix capstone.new` does (plugin application there is deliberately ordered
before dependency work; there's no equivalent ordering constraint here,
since the project already exists). Run it yourself:

```bash
mix deps.get
```

And if the newly-applied plugin included any `:manual` entries — a hunk
spliced into an existing file rather than appended — check for unresolved
conflict regions:

```bash
mix capstone.check
```

## No target, no-op

A directory with no `target.exs` isn't a Capstone project, and
`mix capstone.update` treats it as having nothing to apply — it returns
successfully with an empty list rather than raising. This matches
`plugin.exs` recording's own behavior elsewhere: an untracked target is a
no-op, not an error, since there's no file describing what "newly listed"
would even mean.

## See also

- [Applying a plugin](applying-a-plugin.md) — the resolve → extract → apply
  → record sequence this task shares with `mix capstone.new`.
- [Building a plugin](building-a-plugin.md) — writing the plugin this guide
  assumes already exists somewhere resolvable.
