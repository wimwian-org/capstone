defmodule Capstone.Plugin.Derive do
  @moduledoc """
  Turns an observed diff into a plugin (SDD R1, 10).

  The diff is the source of truth; the manifest is generated from it, not
  written by hand. Derive is a read-modify-write rather than a regenerate:
  `files`, their inferred modes and `deps` are recomputed, and every
  author-owned field is carried across untouched, so 10.1's confirmed
  annotations survive a re-run.

  Input is a RAW working project (`cache_component`); output is the templated
  plugin beside it (`meta_cache`).
  """

  alias Capstone.Plugin
  alias Capstone.Plugin.Classify
  alias Capstone.Plugin.Diff
  alias Capstone.Plugin.MixChanges
  alias Capstone.Source.ApplicationEx
  alias Capstone.Source.ConfigExs
  alias Capstone.Template

  @derived [:files, :deps, :aliases, :project]

  @doc """
  Derives a plugin from a raw working project.

  Options: `:name`, `:baseline`, `:meta` (the raw project), `:names` (the
  `Capstone.Template` name triple) and `:out`.
  """
  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts) do
    changes = Diff.changes(Keyword.fetch!(opts, :baseline), Keyword.fetch!(opts, :meta))

    case changes.removed do
      [] -> emit(opts, changes)
      removed -> {:error, {:unrepresentable_deletions, removed}}
    end
  end

  defp emit(opts, changes) do
    out = Keyword.fetch!(opts, :out)
    {entries, payload} = entries(opts, changes)

    plugin =
      opts
      |> existing(out)
      |> Map.merge(%{name: Keyword.fetch!(opts, :name), files: entries})
      |> Map.merge(recorded_changes(opts, changes))

    Enum.each(payload, fn {relative, contents} ->
      file = Path.join([out, "files", relative])
      File.mkdir_p!(Path.dirname(file))
      File.write!(file, contents)
    end)

    Plugin.write!(Path.join(out, "manifest.exs"), plugin)

    {:ok, plugin}
  end

  # Author-owned fields survive; only @derived are recomputed.
  defp existing(_opts, out) do
    manifest = Path.join(out, "manifest.exs")

    if File.exists?(manifest) do
      manifest |> Plugin.read!() |> Map.drop(@derived)
    else
      %{version: "0.1.0"}
    end
  end

  # Only the keys that carry something are written. `deps:` is always present
  # because SDD 7.1 names it and every existing plugin has it; an empty
  # `aliases:` or `project:` is DROPPED so priv/meta/meta_cache reproduces byte
  # for byte and no plugin gains a key that says nothing.
  defp recorded_changes(opts, changes) do
    %{deps: deps, aliases: aliases, project: project} = mix_changes(opts, changes)

    %{deps: deps}
    |> put_unless_empty(:aliases, aliases)
    |> put_unless_empty(:project, project)
  end

  defp put_unless_empty(map, _key, []), do: map
  defp put_unless_empty(map, key, value), do: Map.put(map, key, value)

  # Three keys, not one. `aliases:` and `project:` are additive siblings of
  # `deps:` rather than a `mix_exs:` block: existing manifest.exs files stay
  # valid and priv/meta/meta_cache does not move.
  defp mix_changes(opts, changes) do
    if "mix.exs" in changes.modified do
      MixChanges.added(
        File.read!(Path.join(Keyword.fetch!(opts, :baseline), "mix.exs")),
        File.read!(Path.join(Keyword.fetch!(opts, :meta), "mix.exs"))
      )
    else
      %{deps: [], aliases: [], project: []}
    end
  end

  # A file may now ship TWO payloads — the block and, when it removes anything,
  # the removed lines — so the payload side is flat-mapped rather than mapped.
  defp entries(opts, changes) do
    names = Keyword.fetch!(opts, :names)
    meta = Keyword.fetch!(opts, :meta)

    owned =
      for path <- changes.added do
        {:ok, template} = Template.capture(File.read!(Path.join(meta, path)), names)
        placeheld = Template.placeholder_path(path, names)
        {{placeheld, :sole_owner}, [{placeheld <> ".eex", template}]}
      end

    pairs = owned ++ shared(opts, changes)

    {Enum.map(pairs, &elem(&1, 0)), Enum.flat_map(pairs, &elem(&1, 1))}
  end

  # mix.exs is matched first and extracted to deps:; without this precedence a
  # dependency line, indented and unparseable alone, becomes a :manual hunk.
  defp shared(opts, changes) do
    name = Keyword.fetch!(opts, :name)
    names = Keyword.fetch!(opts, :names)
    meta = Keyword.fetch!(opts, :meta)
    baseline = Keyword.fetch!(opts, :baseline)

    changes.modified
    |> Enum.reject(&(&1 == "mix.exs"))
    |> Enum.reduce({[], []}, fn path, {acc, taken} ->
      hunks = Diff.hunks(Path.join(baseline, path), Path.join(meta, path))
      block = block(Path.join(baseline, path), Path.join(meta, path), hunks)
      {:ok, templated} = Template.capture(block, names)
      placeheld = Template.placeholder_path(path, names)
      # Keyed from the PLACEHELD path: a key built from the raw one would carry
      # the source project's name into every project the plugin installs to.
      key = Classify.key(name, placeheld, taken)

      sources = {File.read!(Path.join(baseline, path)), File.read!(Path.join(meta, path)), block}
      built = entry(placeheld, hunks, path, key, names, sources)

      # A child: entry carries its whole content in the manifest, so it ships
      # NO payload file — and no removed payload either, which is the point:
      # the comma rewrite that read as a deletion is no longer recorded at all.
      payloads =
        if child_entry?(built),
          do: [],
          else: [
            {placeheld <> ".block.eex", templated} | removed_payload(placeheld, hunks, names)
          ]

      {[{built, payloads} | acc], [key | taken]}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  # A pure append ships the literal suffix rather than a reconstruction from
  # lines. Myers is free to align a blank line at either end of a hunk, and
  # rebuilding from `lines` moved README.md's blank from before the heading to
  # after the body — a difference the round-trip caught. When the meta file is
  # not simply the baseline plus a suffix, fall back to reconstruction.
  defp block(baseline_file, meta_file, hunks) do
    baseline_source = File.read!(baseline_file)
    meta_source = File.read!(meta_file)

    if String.starts_with?(meta_source, baseline_source) do
      String.replace_prefix(meta_source, baseline_source, "")
    else
      hunks |> Enum.flat_map(& &1.lines) |> Enum.map_join("", &(&1 <> "\n"))
    end
  end

  # An anchor lets apply PLACE a positional hunk instead of marking it, so it is
  # recorded for :manual entries only — :contributes appends and needs no
  # position. The anchor is templated like any other content: it is matched
  # against a target whose project name differs.
  defp entry(placeheld, hunks, path, key, names, sources) do
    case file_mode(hunks, path, sources) do
      :child ->
        {placeheld, :contributes, [key: key, child: added_child(sources, names)]}

      :contributes ->
        {placeheld, :contributes, [key: key] ++ placement(path, sources)}

      :manual ->
        anchor =
          hunks
          |> List.first(%{anchor: []})
          |> Map.fetch!(:anchor)
          |> Enum.map(&capture!(&1, names))

        {placeheld, :manual, [after: anchor, key: key]}
    end
  end

  # WHERE the contribution was observed, decided by replaying each placement
  # against the baseline and keeping the one that reproduces the meta file.
  # The writer is the oracle: no line arithmetic, no guessing, and a config
  # file's round trip is guaranteed by construction rather than by inspection.
  #
  # `:append` is omitted rather than recorded, so a plugin that simply
  # appends gains no key and priv/meta/meta_cache does not move.
  defp placement(path, sources) do
    if config_file?(path), do: observed_placement(sources), else: []
  end

  # A config contribution whose observed placement no replay reproduces cannot
  # be applied automatically: apply would append it, and appending is what puts
  # a block below import_config where it outranks the project's own env files.
  # Loud beats wrong, so it falls through to :manual and mix capstone.check.
  defp unplaceable?(path, sources) do
    config_file?(path) and observed_placement(sources) == [] and not appends?(sources)
  end

  defp appends?({baseline_source, meta_source, block}),
    do: baseline_source <> block == meta_source

  defp config_file?(path), do: Path.dirname(path) == "config"

  @environments [:dev, :test, :prod]

  # `:append` is tested FIRST and omitted when it wins. It has to be: a file
  # with no import_config makes insert_before_import/2 append, so that function
  # reproduces the append case too and would record a placement saying nothing.
  defp observed_placement({baseline_source, meta_source, block} = sources) do
    if appends?(sources) do
      []
    else
      [:before_import | Enum.map(@environments, &{:env, &1})]
      |> Enum.find(&reproduces?(baseline_source, meta_source, block, &1))
      |> case do
        nil -> []
        at -> [at: at]
      end
    end
  end

  defp reproduces?(baseline_source, meta_source, block, at) do
    case place(baseline_source, block, at) do
      {:ok, patched} -> patched == meta_source
      {:error, _reason} -> false
    end
  end

  defp place(source, block, :before_import), do: ConfigExs.insert_before_import(source, block)
  defp place(source, block, {:env, env}), do: ConfigExs.insert_in_env(source, env, block)

  # A SECOND payload beside the block, written only when the file removes
  # something. Its ABSENCE is the signal apply reads. An option on the manifest
  # entry would have widened SDD 7.1, which R4 requires stable.
  #
  # Joined WITHOUT a trailing newline: apply's idempotency probe is a substring
  # test against the target, and a removal at the end of a file that has no
  # trailing newline would never match one.
  defp removed_payload(placeheld, hunks, names) do
    removed = hunks |> Enum.flat_map(& &1.removed) |> Enum.join("\n")

    if Enum.any?(hunks, &(&1.removed != [])),
      do: [{placeheld <> ".removed.eex", capture!(removed, names)}],
      else: []
  end

  defp capture!(source, names) do
    {:ok, templated} = Template.capture(source, names)
    templated
  end

  # 7.3's FileEntry carries ONE mode per path, so a file's hunks are classified
  # together rather than individually. The merge is deliberately conservative: a
  # single structural hunk makes the whole file :manual, because shipping the
  # rest as an appendable block would write the appendable part automatically
  # and silently drop the part that needed a human.
  #
  # A deletion outranks Classify entirely. `:contributes` APPENDS, and appending
  # cannot remove anything, so a file that removes lines has no representation
  # but a conflict region — whatever its extension says about the added half.
  defp file_mode(hunks, path, sources) do
    cond do
      added_child(sources, nil) != nil -> :child
      Enum.any?(hunks, &(&1.removed != [])) -> :manual
      placed?(path, sources) -> :contributes
      unplaceable?(path, sources) -> :manual
      Enum.all?(hunks, &(Classify.bucket(&1.lines, path) == :contributes)) -> :contributes
      true -> :manual
    end
  end

  defp child_entry?({_path, :contributes, opts}), do: Keyword.has_key?(opts, :child)
  defp child_entry?(_entry), do: false

  # The ONE supervision shape with a deterministic answer: the meta project
  # added children to `start/2` and changed nothing else. Recognised by
  # replaying `add_child/2` against the baseline — the writer is the oracle, as
  # it is for config placement — so a diff that also touches `strategy:` or the
  # function body does not reproduce and falls through to the existing loud
  # `:manual` path with its removals intact.
  #
  # `names` is nil when only recognition is wanted; the child is templated only
  # once an entry is actually being built.
  defp added_child({baseline_source, meta_source, _block}, names) do
    with {:ok, before} <- ApplicationEx.children(baseline_source),
         {:ok, after_} <- ApplicationEx.children(meta_source),
         [child] <- after_ -- before,
         {:ok, ^meta_source} <- ApplicationEx.add_child(baseline_source, child) do
      if names, do: capture!(child, names), else: child
    else
      _no_match -> nil
    end
  end

  # A proven placement outranks Classify's column-0 rule. That rule exists
  # because APPENDING an indented line produces code that does not compile —
  # but a contribution inside `if config_env() == :prod do` is indented by
  # definition, and here it is not being appended: the replay reproduced the
  # meta file byte for byte, so the site is known rather than guessed.
  defp placed?(path, sources), do: config_file?(path) and placement(path, sources) != []
end
