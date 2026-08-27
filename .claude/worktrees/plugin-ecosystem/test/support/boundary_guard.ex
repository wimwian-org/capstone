defmodule Capstone.BoundaryGuard do
  @moduledoc """
  Mechanical enforcement of the ambient-state ban.

  F4 was ambient state, and a rule expressed in prose rots. Several moduledocs
  under `lib/` already word themselves around "what BoundaryGuard bans";
  without this module they were describing a rule nothing checked.

  It lives under `test/support/` rather than `lib/` because it is a check on
  the source, not a part of the tool: `mix.exs` puts `test/support` on
  `elixirc_paths` in `:test` only, so it compiles for the suite and ships in no
  release.

  Ported from a two-perimeter design (`apps/capstone` and the separate
  `apps/capstone_new` archive it shipped alongside): this package has one
  perimeter, `lib/`, so `banned/1`'s old `:capstone_new` clause — which
  existed only to omit `String.to_atom` for the installer's own reasons — no
  longer has a separate perimeter to attach to. `Capstone.Config.Project`,
  formerly compiled only under that omitted perimeter, is exempt by name
  instead — see `exempt/0`.
  """

  @shared [
    "Mix.Project.",
    "Mix.env",
    "File.cd",
    "__DIR__",
    "Code.eval_string",
    "Code.eval_file",
    "Code.require_file",
    "Code.compile_file",
    "DateTime.utc_now",
    "NaiveDateTime.utc_now",
    "System.system_time",
    ":rand.",
    "System.unique_integer",
    "make_ref",
    "rescue _ ->"
  ]

  # A LIST OF NAMES, never a pattern. A pattern would let a second exemption
  # arrive by accident; a name makes each one a visible decision, and
  # `Capstone.BoundaryGuardTest` asserts this list's exact contents, so adding to it
  # fails a test rather than passing unnoticed.
  @exempt ["lib/capstone/clock.ex", "lib/capstone/config/project.ex"]

  # The one PREFIX, and the reason it is a prefix rather than a name: this is
  # other people's source, vendored under `lib/` so hex ships it, and it is
  # ~76 files that change wholesale on every vendor update. Naming each one
  # would churn on every bump and say nothing.
  #
  # It is not a hole in the ban so much as the edge of what the ban is about:
  # the rule governs code Capstone writes. Every other tool here draws the same
  # line -- `.formatter.exs` computes its inputs to skip it, `coveralls.json`
  # lists it under skip_files, `.dialyzer_ignore.exs` carries `~r"^lib/capstone/
  # vendor/"` -- and `scripts/vendor.exs check` is what actually guards this
  # tree, by digest.
  @vendor "lib/capstone/vendor/"

  @doc "The banned tokens for this package's one perimeter."
  @spec banned() :: [binary()]
  def banned, do: ["String.to_atom" | @shared]

  @doc """
  The files `scan/2` does not read, as literal repo-relative paths.

  Two, each for a different token:

    * `lib/capstone/clock.ex` — `plugin.exs` requires `generated_at` and
      `applied_at` as ISO8601-Z strings and its caller is a mix task, which is
      under `lib/` — so the format requires a timestamp this guard forbids
      producing anywhere. One named module owns that interaction, the way
      `Capstone.Root` owns the project root.
    * `lib/capstone/config/project.ex` — derives a project's `:app` atom from
      its `name:` string (`String.to_atom/1`) when `fields[:app]` is omitted.
      `String.to_existing_atom/1` cannot substitute: the whole point is
      accepting a project name never seen in this VM before.
      `mix capstone.new` reads exactly one `target.exs` per invocation and
      exits, so this is bounded, one-shot atom creation — not the unbounded,
      attacker-driven kind the ban exists to catch.

  Holes widen. If a third exemption is ever proposed, that is the moment to
  ask whether the ban is still carrying its weight.
  """
  @spec exempt() :: [Path.t()]
  def exempt, do: @exempt

  @doc "Returns the banned tokens present in `source`."
  @spec violations(binary(), [binary()]) :: [binary()]
  def violations(source, banned), do: Enum.filter(banned, &String.contains?(source, &1))

  @doc """
  The vendored subtree `scan/2` does not read, as a repo-relative path prefix.
  """
  @spec vendor() :: Path.t()
  def vendor, do: @vendor

  @doc """
  Maps each `.ex` under `dir` to its violations, omitting clean, exempt and
  vendored files.
  """
  @spec scan(Path.t(), [binary()]) :: %{optional(Path.t()) => [binary()]}
  def scan(dir, banned) do
    dir
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.reject(&(&1 in @exempt or String.starts_with?(&1, @vendor)))
    |> Map.new(&{&1, violations(File.read!(&1), banned)})
    |> Map.reject(fn {_path, hits} -> hits == [] end)
  end
end
