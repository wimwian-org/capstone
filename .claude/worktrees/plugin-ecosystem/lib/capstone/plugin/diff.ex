defmodule Capstone.Plugin.Diff do
  @moduledoc """
  Compares a meta project against its baseline (SDD R1).

  The diff is the feature's definition — observed, never guessed — so this
  module reports what changed without interpreting it.
  `Capstone.Plugin.Classify` decides what each change means.
  """

  alias Capstone.Baseline

  @anchor_lines 3

  @doc """
  Partitions relative paths into added, modified and removed.

  Comparison is by content hash from `Capstone.Baseline.tree/1`, which prunes
  `.git`, `deps` and `_build` and placeholders phx.new's random secrets, so a
  regenerated meta project does not read as drift.
  """
  @spec changes(Path.t(), Path.t()) :: %{
          added: [Path.t()],
          modified: [Path.t()],
          removed: [Path.t()]
        }
  def changes(baseline_dir, meta_dir) do
    baseline = Baseline.tree(baseline_dir)
    meta = Baseline.tree(meta_dir)

    %{
      added: meta |> Map.drop(Map.keys(baseline)) |> Map.keys() |> Enum.sort(),
      removed: baseline |> Map.drop(Map.keys(meta)) |> Map.keys() |> Enum.sort(),
      modified:
        baseline
        |> Enum.filter(fn {path, hash} -> Map.has_key?(meta, path) and meta[path] != hash end)
        |> Enum.map(fn {path, _hash} -> path end)
        |> Enum.sort()
    }
  end

  @doc """
  The lines `meta_file` adds and removes relative to `baseline_file`, one entry
  per hunk.

  Each carries the `lines` added, the `removed` lines they replace, and the
  `anchor` they followed — up to three preceding lines of unchanged text. Three,
  not one: a single line of context is routinely ambiguous in Elixir source,
  where `  end` and a docstring's closing delimiter repeat within one file, and
  placing against an ambiguous anchor puts code in the wrong place silently.
  `anchor` is `[]` for a hunk at the start of a file.

  A deletion is HELD rather than emitted, because Myers writes a replacement as
  `{:del, old}` immediately followed by `{:ins, new}` and the two halves belong
  in one hunk. A deletion followed by anything else — unchanged text, or the end
  of the diff — becomes a hunk of its own with `lines: []`. Nothing is
  discarded: dropping `{:del, _}` is what let a REWRITTEN file classify as
  `:contributes` and apply as an append, producing a file holding both the old
  content and the new while reporting `:ok`.

  A deletion does not advance the context, so a replacement anchors on the
  unchanged text that preceded what it replaced.

  Indentation is preserved deliberately: it is what tells a top-level block from
  an insertion inside an existing literal.
  """
  @spec hunks(Path.t(), Path.t()) :: [
          %{anchor: [binary()], lines: [binary()], removed: [binary()]}
        ]
  def hunks(baseline_file, meta_file) do
    old = baseline_file |> File.read!() |> String.split("\n")
    new = meta_file |> File.read!() |> String.split("\n")

    # `pending` holds at most one deletion chunk. Myers never emits two in a
    # row — it coalesces adjacent chunks of the same kind — so the empty-list
    # pattern below is exhaustive for every diff it can produce, and a
    # FunctionClauseError is the right answer if that ever stops being true.
    {context, pending, found} =
      Enum.reduce(List.myers_difference(old, new), {[], [], []}, fn
        {:del, lines}, {context, [], found} ->
          {context, lines, found}

        {:ins, lines}, {context, pending, found} ->
          {context, [], [hunk(context, lines, pending) | found]}

        {:eq, lines}, {context, pending, found} ->
          {Enum.take(lines, -@anchor_lines), [], flush(context, pending, found)}
      end)

    context |> flush(pending, found) |> Enum.reverse()
  end

  defp hunk(anchor, lines, removed), do: %{anchor: anchor, lines: lines, removed: removed}

  defp flush(_anchor, [], found), do: found
  defp flush(anchor, pending, found), do: [hunk(anchor, [], pending) | found]
end
