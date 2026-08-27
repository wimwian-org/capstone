# What is vendored, at which version, and what we changed.
#
# `digest` is a SHA-256 over the vendored tree as it stands **after** the
# patches below, so `elixir scripts/vendor.exs check` detects a local edit as
# readily as an upstream change. Regenerate it with
# `elixir scripts/vendor.exs record NAME`.
#
# `roots` are the top-level module namespaces rewritten to `Capstone.Vendor.*` by
# `elixir scripts/vendor.exs namespace`. Vendoring dodges a *version* conflict;
# it does nothing about a *module name* conflict, and a target project using
# Igniter or Ash already defines `Sourceror`. Two definitions of one module is
# the archive-shadowing failure (E2) wearing different clothes.
#
# Read as data, never evaluated by the build.
%{
  simple_enum: %{
    digest: "fe063f74fd805cfba9f039d5dd9eedb24ec01f1646a1d8dac76f9caee7d1197d",
    roots: ["SimpleEnum"],
    version: "1.0.0",
    licence: "MIT",
    author: "DarkyZ aka NotAVirus",
    source: "https://github.com/ImNotAVirus/simple_enum",
    used_for: "enumerated section values in target.exs",
    patches: []
  },
  sourceror: %{
    digest: "d881ac674ce68774254854a21c77374c53b26dd45b2ff1868b76d3420eafd0e2",
    roots: ["Sourceror"],
    version: "1.12.2",
    licence: "Apache-2.0",
    author: "doorgan",
    source: "https://github.com/doorgan/sourceror",
    used_for: "structural placement -- parse and patch by range",
    patches: [
      """
      lib/sourceror.ex:2 -- `@external_resource "README.md"` resolved against the
      *host* project root, so the moduledoc was built from Capstone's README and the
      compile died in `Enum.fetch!/2` looking for a `<!-- MDOC !-->` marker that
      is not there. Anchored to `__DIR__`, which is the idiom upstream
      simple_enum already uses.
      """
    ]
  },
  typedstruct: %{
    digest: "e30c0ac8f5ae1fbdd874c8a0ebebc77945fb51f06d381947cae1d6da88b278c2",
    roots: ["TypedStruct"],
    version: "0.5.4",
    licence: "MIT",
    author: "Jean-Philippe Cugnet and contributors",
    source: "https://github.com/saleyn/typedstruct",
    used_for: "the config and manifest structs",
    patches: [
      """
      lib/typed_struct.ex:2-3 -- same relative-`README.md` defect as sourceror,
      in both `@external_resource` and `@moduledoc`. Anchored to `__DIR__`.
      """
    ]
  },
  vex: %{
    digest: "855aa2b24d5517f21fbb20602bcce2b8d6d5cc887039ef6049f00ae1b494b4c8",
    roots: ["Vex"],
    version: "0.9.2",
    licence: "MIT",
    author: "Bruce Williams",
    source: "https://github.com/CargoSense/vex",
    used_for: "validating target.exs sections",
    patches: [
      """
      lib/vex/error_renderer.ex:11 -- a stray closing ``` in the `@moduledoc`
      opens a fenced code block that nothing closes, so `mix docs` warns
      "Fenced Code Block opened with ``` not closed at end of input". Upstream
      defect, unrelated to namespacing. The line is deleted; no prose is lost,
      because there is no opening fence for it to have closed.
      """
    ]
  }
}
