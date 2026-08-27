defmodule Capstone.Plugin.MixChanges do
  @moduledoc """
  Reads what a raw working project changed in `mix.exs` (SDD R1, D10).

  Structural, not textual: a line diff cannot tell a new dependency from a
  reflowed one, and D10 restricts a plugin's `deps:` to target-facing
  dependencies, so each construct is read from the AST rather than from the
  shape of the file.

  Every parse is delegated to `Capstone.Source.MixExs`, so the capture side and the
  apply side cannot disagree about what a deps list looks like. They did:
  measured, the reader matched two of the four shapes `mix` accepts and the
  writer matched one, and each reported success on the shapes it could not
  handle.

  Renamed from `Capstone.Plugin.Deps`. The question widened from "which
  dependencies?" to "which dependencies, aliases and project keys?", and a
  module called `Deps` answering all three would be a name that lies.
  """

  alias Capstone.Source.MixExs

  @typedoc "What a plugin's meta-project declares in `mix.exs` beyond its baseline — the shape `Capstone.Plugin.Behavior.deps/0` and friends are captured into."
  @type t :: %{deps: [binary()], aliases: keyword(), project: keyword()}

  @doc """
  What `meta_source` declares that `baseline_source` does not.

  Aliases and project keys whose VALUE changed are reported alongside new keys:
  a plugin that rewrites `setup:` is contributing that rewrite, and it has no
  representation if only additions count.
  """
  @spec added(binary(), binary()) :: t()
  def added(baseline_source, meta_source) do
    %{
      deps: new_entries(&MixExs.deps/1, baseline_source, meta_source),
      aliases: new_entries(&MixExs.aliases/1, baseline_source, meta_source),
      project: new_entries(&MixExs.project_keys/1, baseline_source, meta_source)
    }
  end

  # An unreadable or absent construct reports NOTHING CHANGED rather than
  # raising: a meta project with no aliases/0 is the ordinary case, and derive
  # must not fail on it. Apply is where an unlocatable construct is loud,
  # because that is where it would otherwise be silently skipped.
  # OBSERVED order, not sorted. File order is already deterministic, and it is
  # the only order that lets apply reproduce the meta project byte for byte —
  # sorting made the round trip fail on both the dependency list and the alias
  # list, in different directions.
  defp new_entries(read, baseline_source, meta_source) do
    existing = entries(read, baseline_source)

    read
    |> entries(meta_source)
    |> Enum.reject(&(&1 in existing))
  end

  defp entries(read, source) do
    case read.(source) do
      {:ok, entries} -> entries
      {:error, _reason} -> []
    end
  end
end
