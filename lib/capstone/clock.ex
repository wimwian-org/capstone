defmodule Capstone.Clock do
  @moduledoc """
  The wall clock, as the one module under `lib/` allowed to read it.

  `plugin.exs` requires `generated_at` and `applied_at` as ISO8601-Z strings
  (SDD 8.2). `Capstone.Manifest` deliberately mints neither — its moduledoc
  states they are caller-supplied — and the caller is a mix task, which is also
  under `lib/`, where `Capstone.BoundaryGuard` bans every way of asking what
  time it is. The format therefore requires something the codebase's own rules
  forbid producing anywhere, and this module is the resolution:
  `Capstone.BoundaryGuard.exempt/0` names this ONE file, by name and not by
  pattern, so a second exemption has to be a visible decision.

  This follows `Capstone.Root`, which exists for the same class of problem —
  one narrow module owning an unavoidable interaction with the outside world.

  D8's determinism argument is untouched. D8 constrains GENERATED OUTPUT —
  "same inputs, same bytes" — because D7 regenerates a historical baseline and
  diffs it. A lock file records history, not output; `Capstone.Baseline` and
  `Capstone.Plugin.Derive` remain byte-deterministic and keep their tests.
  """

  @doc """
  The current instant, as the ISO8601-Z string `plugin.exs` requires.

  Microsecond precision, which is what the renderer emits and what
  `Capstone.Manifest.validate_timestamp!/2` round-trips: that validator rejects
  any spelling it could not reproduce byte for byte, `+00:00` included.
  """
  @spec now() :: String.t()
  def now, do: DateTime.to_iso8601(DateTime.utc_now())
end
