# Vendored libraries

Four libraries compiled directly into Capstone from source rather than resolved as
Hex dependencies. Each directory is the **unpacked hex tarball**, kept whole —
`lib/`, licence, `CHANGELOG.md`, `README.md`, `hex_metadata.config` and upstream
`mix.exs` — so a freshly fetched tree can be compared against the vendored one
byte for byte. Only `lib/` is compiled.

## Why vendored

Capstone is installed as a dev dependency **inside someone else's project**. Every
requirement it declared would become a constraint on that project's resolution,
and a project already using Igniter or Ash carries its own Sourceror pin. A
scaffolder that can be locked out of a project by a version conflict cannot run
the update six months later, which is the one thing it exists to do.

This is separate from the archive's zero Hex requirements: the archive is its
own Mix project with its own empty dependency list, and the two ebins are
disjoint, so nothing here affects it either way.

## What is vendored

| Library                                                     | Version | Licence    | Author                                | Used for                                        |
| ----------------------------------------------------------- | ------- | ---------- | ------------------------------------- | ----------------------------------------------- |
| [`sourceror`](https://github.com/doorgan/sourceror)         | 1.12.2  | Apache-2.0 | doorgan                               | structural placement — parse and patch by range |
| [`vex`](https://github.com/CargoSense/vex)                  | 0.9.2   | MIT        | Bruce Williams                        | validating `target.exs` sections                |
| [`typedstruct`](https://github.com/saleyn/typedstruct)      | 0.5.4   | MIT        | Jean-Philippe Cugnet and contributors | the config and manifest structs                 |
| [`simple_enum`](https://github.com/ImNotAVirus/simple_enum) | 1.0.0   | MIT        | DarkyZ aka NotAVirus                  | enumerated section values                       |

These are other people's work carrying other people's licences. Nothing here is
formatted, linted, doc-checked or coverage-counted by this project's gates, and
the vendored modules are filtered out of the published docs — their API is
theirs, not ours.

`vendor/vendor.exs` is the record: version, licence, author, source, and every
patch, with a SHA-256 digest of each tree as vendored.

## Recorded patches

Three, against two defects. The first two are load-bearing: without them Capstone
does not compile.

**`sourceror/lib/sourceror.ex:2`** and **`typedstruct/lib/typed_struct.ex:2-3`**
build their `@moduledoc` from `File.read!("README.md")` with a *relative* path.
Compiled inside Capstone that resolves against **Capstone's** project root, so the
moduledoc was assembled from Capstone's own README and the build died in
`Enum.fetch!/2` looking for a `<!-- MDOC !-->` marker that is not there.

Both are anchored to `__DIR__` instead:

```elixir
@external_resource [__DIR__, "..", "README.md"] |> Path.join() |> Path.expand()
```

That is the idiom upstream `simple_enum` already uses, which is why it needed no
patch. `vex` reads nothing at compile time.

**`vex/lib/vex/error_renderer.ex:11`** carried a stray closing ` ``` ` inside its
`@moduledoc`. With no opening fence to match, Earmark reads it as a code block
that runs to the end of input, and `mix docs` warns accordingly. The line is
deleted. Cosmetic rather than load-bearing — it costs a warning, not a build —
and no prose is lost, since the fence closed nothing.

## Namespacing

Every vendored root is rewritten to `Capstone.Vendor.*` — `Capstone.Vendor.Sourceror`,
`Capstone.Vendor.Vex`, `Capstone.Vendor.TypedStruct`, `Capstone.Vendor.SimpleEnum`, 65
modules in all.

Vendoring solves a **version** conflict. It does nothing about a **module name**
conflict, and a target project using Igniter or Ash already defines `Sourceror`.
Two definitions of one module is failure mode E2 — archive-resident module
shadowing — wearing different clothes, and it would land in a project Capstone was
supposed to leave alone.

`override: true` is not an alternative to either. Reproduced: it is honoured
only in the **top-level** project and silently ignored inside a dependency, so
the version conflict resolves only if every user adds an override to their own
`mix.exs` for a dev-only scaffolder they did not ask to think about.

The rewrite is mechanical, declared per library as `roots:` in `vendor.exs`, and
re-applied automatically on every `update` — never a patch anyone has to
remember. `check` fails while a bare root survives, which is what stops a fetch
from quietly undoing it.

It rewrites the root token wherever it appears, docstrings included, so vendored
prose reads `Capstone.Vendor.Sourceror`. Harmless: `filter_modules` in `mix.exs`
excludes the whole namespace from the published docs.

## Keeping it honest

```sh
elixir scripts/vendor.exs check                    # digests match, nothing un-namespaced
elixir scripts/vendor.exs namespace sourceror      # re-apply the Capstone.Vendor.* rewrite
elixir scripts/vendor.exs outdated                 # newer releases on hex
elixir scripts/vendor.exs update sourceror 1.13.0  # re-vendor
elixir scripts/vendor.exs record sourceror         # re-record after patching
```

`check` compares a SHA-256 over each tree **as vendored, patches included** —
not hex's checksum, which identifies an unmodified release and would therefore
report our intended state as a failure. It catches an upstream bump and a
stray local edit with equal indifference, which is the property that matters.

`update` reads the patched files before it overwrites them and tells you which
of them upstream also changed. **It never re-applies a patch for you.** A patch
silently dropped is a compile failure at best and a behaviour change at worst,
so the script's job ends at telling you exactly which files need hand-work.

After any update: re-apply the patches, `mix compile`, then `record`.

## Dialyzer

`.dialyzer_ignore.exs` filters `~r"^vendor/"` — eight warnings in sourceror
1.12.2's zipper and `code/common` modules. Upstream's specs, not ours.
`list_unused_filters: true` means that filter starts failing the run the moment
upstream fixes them, which is the signal to delete it.
