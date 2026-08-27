defmodule Capstone.Plugin.Apply do
  @moduledoc """
  Installs a derived plugin into a target project (SDD 7.3).

  Apply never matches a project name — all matching happened at capture. It
  renders `<%= @app %>` and resolves the bare `APP` path token, both from the
  target's own triple, then writes each entry according to its ownership mode.

  Applying is also RECORDING, when the target declares itself: see
  `Capstone.Plugin.Record`, which reads back every file this module wrote and
  writes the manifest a later update diffs.
  """

  alias Capstone.Plugin
  alias Capstone.Plugin.Record
  alias Capstone.Source.ApplicationEx
  alias Capstone.Source.ConfigExs
  alias Capstone.Source.MixExs
  alias Capstone.Template

  @doc """
  Applies the plugin at `component_dir` to `target`.

  The target's own `mix.exs` supplies the name triple, so a plugin installs
  into any project rather than only one recorded in `priv/baselines.exs`.

  A target holding a `target.exs` also gets a `plugin.exs` recording what
  was written; one without is installed and records nothing. See
  `Capstone.Plugin.Record`.

  `opts` is forwarded to `Capstone.Plugin.Record.run/5` verbatim. `opts[:origin]`
  overrides the recorded origin — used when `component_dir` is a temporary
  directory a packaged archive was extracted into, which would otherwise be
  recorded as a `{:path, _}` pointing at a directory deleted moments later.
  """
  @spec run(Path.t(), Path.t(), keyword()) :: {:ok, map()}
  def run(component_dir, target, opts \\ []) do
    plugin = Plugin.read!(Path.join(component_dir, "manifest.exs"))
    names = names(target)

    Record.preflight!(target)
    Enum.each(plugin.files, &entry(&1, component_dir, target, names))
    add_deps(target, plugin.deps)
    # Map.get/3 with a default, not fetch!/2: every plugin written before
    # these keys existed has neither, and must keep working untouched.
    put_aliases(target, Map.get(plugin, :aliases, []))
    put_project_keys(target, Map.get(plugin, :project, []))
    Record.run(component_dir, target, plugin, names, opts)

    {:ok, plugin}
  end

  defp entry({path, :sole_owner}, dir, target, names) do
    write_owned(target, path, payload(dir, path <> ".eex"), names)
  end

  # A `child:` entry ships NO payload file: the child is one expression, small
  # enough to live in the manifest, and Template.render/2 resolves it like any
  # other payload.
  defp entry({path, :contributes, opts}, dir, target, names) do
    case Keyword.fetch(opts, :child) do
      {:ok, child} -> add_supervision_child(target, path, child, names)
      :error -> contribute(target, path, payload(dir, path <> ".block.eex"), names, opts)
    end
  end

  # Dispatched on whether the removed payload FILE exists, never on whether its
  # contents are empty: a plugin that removes one blank line renders to an
  # empty payload, and dispatching on emptiness would drop it silently — the
  # defect class this path exists to close.
  # `opts` is a KEYWORD LIST, so the put: test cannot be a guard — Keyword
  # functions are not guard-safe, and is_map_key/2 on a list is silently false.
  defp entry({path, :manual, opts}, dir, target, names) do
    if Keyword.has_key?(opts, :put) do
      # A `put:` entry names a key that must ALREADY exist in the target: it
      # overrides rather than contributes, so it is :manual by mode and yet has
      # a deterministic action, and never reaches the marker path.
      put_config_key(target, path, payload(dir, path <> ".block.eex"), names, opts)
    else
      place_manual(path, opts, dir, target, names)
    end
  end

  defp place_manual(path, opts, dir, target, names) do
    removed = Path.join([dir, "files", path <> ".removed.eex"])

    if File.exists?(removed) do
      mark_removal(
        target,
        path,
        payload(dir, path <> ".block.eex"),
        Keyword.fetch!(opts, :key),
        names,
        File.read!(removed)
      )
    else
      place(
        target,
        path,
        payload(dir, path <> ".block.eex"),
        Keyword.fetch!(opts, :key),
        Keyword.get(opts, :after, []),
        names
      )
    end
  end

  defp payload(dir, relative), do: File.read!(Path.join([dir, "files", relative]))

  @doc """
  The `Capstone.Template` name triple for `target_dir`, read from its `mix.exs`.

  Read structurally rather than guessed from the directory name: a project's
  directory and its `app:` need not agree, and 8.1 states `name:` is
  independent of `app:`.
  """
  @spec names(Path.t()) :: Template.names()
  def names(target_dir) do
    app = app_name!(target_dir)

    %{module: Macro.camelize(app), app: app, name: app}
  end

  @doc """
  Writes a `:sole_owner` entry: the whole rendered file at the resolved path.

  The plugin is the only author, so this overwrites without asking. Doing so
  for any other mode would be a first-order R6 violation.
  """
  @spec write_owned(Path.t(), Path.t(), binary(), Template.names()) :: :ok
  def write_owned(target, path, template, names) do
    file = Path.join(target, Template.resolve_path(path, names))
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, Template.render(template, names))
  end

  @doc """
  Places a `:contributes` block where the entry's `at:` option says.

  `at:` is RECORDED by derive from where the hunk was observed, never inferred
  here: apply cannot tell from a block of text whether it belongs above
  `import_config`, inside a `config_env()` guard, or at the end — and guessing
  is how a production secret becomes a test default.

  Defaults to `:append`, so every plugin written before `at:` existed keeps
  its exact behaviour.

  Raises `Capstone.Source.ConfigExs.Error` when the named site is absent.
  """
  @spec contribute(Path.t(), Path.t(), binary(), Template.names(), keyword()) :: :ok
  def contribute(target, path, template, names, opts) do
    file = Path.join(target, Template.resolve_path(path, names))
    block = Template.render(template, names)

    case place_contribution(File.read!(file), block, Keyword.get(opts, :at, :append)) do
      {:ok, patched} -> File.write!(file, patched)
      {:error, reason} -> raise ConfigExs.Error, "#{file}: #{inspect(reason)}"
    end
  end

  @doc """
  Appends a supervision child to the target's `application.ex`.

  Placed rather than marked. Adding a list element rewrites the previous last
  entry to gain a comma, which reads as a deletion and forced the whole file to
  a conflict region on every install — see
  `Capstone.Source.ApplicationEx`, which removes that cause.

  Raises `Capstone.Source.ApplicationEx.Error` when the `children` list cannot be
  located: a plugin whose process is never started did nothing, and saying
  `:ok` for it is the silent-success shape this subsystem exists to remove.
  """
  @spec add_supervision_child(Path.t(), Path.t(), binary(), Template.names()) :: :ok
  def add_supervision_child(target, path, child, names) do
    file = Path.join(target, Template.resolve_path(path, names))

    case ApplicationEx.add_child(File.read!(file), Template.render(child, names)) do
      {:ok, patched} -> File.write!(file, patched)
      {:error, reason} -> raise ApplicationEx.Error, "#{file}: #{inspect(reason)}"
    end
  end

  @doc """
  Replaces one key of an existing `config` statement, per the entry's `put:`.

  The key must already be there. Raises `Capstone.Source.ConfigExs.Error` otherwise:
  an override that silently becomes an insert is a typo turned into a config
  key nobody reads.
  """
  @spec put_config_key(Path.t(), Path.t(), binary(), Template.names(), keyword()) :: :ok
  def put_config_key(target, path, template, names, opts) do
    file = Path.join(target, Template.resolve_path(path, names))
    {statement, key} = Keyword.fetch!(opts, :put)
    value = template |> Template.render(names) |> String.trim_trailing("\n")

    case ConfigExs.put_key(File.read!(file), statement, key, value) do
      {:ok, patched} -> File.write!(file, patched)
      {:error, reason} -> raise ConfigExs.Error, "#{file}: #{inspect(reason)}"
    end
  end

  # 7.3 requires "present and unchanged -> no-op". Presence is a substring test
  # rather than a marker comment: contributing files span Elixir, YAML,
  # JavaScript and Markdown, which share no comment syntax.
  defp place_contribution(source, block, :append),
    do: {:ok, if(String.contains?(source, block), do: source, else: source <> block)}

  defp place_contribution(source, block, :before_import),
    do: ConfigExs.insert_before_import(source, block)

  defp place_contribution(source, block, {:env, env}),
    do: ConfigExs.insert_in_env(source, env, block)

  # Assembled rather than written whole, so no source file in this project
  # contains the marker literally. `mix capstone.check` scans every file it is
  # pointed at, and a tool that writes markers must not flag its own source --
  # the same reason Capstone.Manifest words its docs around BoundaryGuard.
  @open String.duplicate("<", 7)
  @close String.duplicate(">", 7)
  @half String.duplicate("-", 7)

  @doc "The opening marker line for `key`, which `mix capstone.check` looks for."
  @spec marker_prefix(atom() | binary()) :: binary()
  def marker_prefix(key), do: "#{@open} capstone: #{key}"

  @doc """
  Places a `:manual` hunk against its recorded anchor.

  Inserts immediately after the anchor when it occurs EXACTLY once. Anything
  else — absent, empty, or more than one match — falls back to a keyed conflict
  region at the end of the file, which will not compile until a human moves it.

  Exactly-once is the whole safety argument. An anchor matching twice means
  there is no way to tell which site the author meant, and inserting at the
  first is a silent wrong answer; a marker is a loud one. `mix capstone.check`
  fails while any marker remains, and D12 forbids resolving it with a prompt.
  """
  @spec place(Path.t(), Path.t(), binary(), atom(), [binary()], Template.names()) :: :ok
  def place(target, path, template, key, anchor, names) do
    file = Path.join(target, Template.resolve_path(path, names))
    current = File.read!(file)
    block = Template.render(template, names)
    needle = Enum.map_join(anchor, "\n", &Template.render(&1, names))

    cond do
      # Presence first, and it is NOT redundant with the marker check: once a
      # hunk is placed, its anchor is still there and still unique, so without
      # this a second apply inserts the block again.
      String.contains?(current, block) -> :ok
      String.contains?(current, marker_prefix(key)) -> :ok
      anchor == [] -> mark(file, current, block, key)
      occurrences(current, needle) == 1 -> insert_after(file, current, needle, block)
      true -> mark(file, current, block, key)
    end
  end

  @doc """
  Marks a `:manual` hunk that also REMOVES lines, always as a conflict region.

  Never anchored. `place/6`'s insert path would write the added lines in and
  leave the removed ones behind, which is the silent success this exists to
  close — a file holding both the old content and the new, and `:ok` returned.

  Idempotent on the REMOVED half rather than the added one. `place/6` re-applies
  as a no-op because its block survives verbatim; a human resolving a removal
  necessarily deletes text, so that probe stops holding here, and a hunk that
  only deletes has no added block to probe at all — a substring test against an
  empty needle is always true, which would make the FIRST apply a no-op and
  write nothing. Removed text already absent means the edit has been made.
  """
  @spec mark_removal(Path.t(), Path.t(), binary(), atom(), Template.names(), binary()) :: :ok
  def mark_removal(target, path, template, key, names, removed_template) do
    file = Path.join(target, Template.resolve_path(path, names))
    current = File.read!(file)
    removed = Template.render(removed_template, names)

    cond do
      String.contains?(current, marker_prefix(key)) -> :ok
      not String.contains?(current, removed) -> :ok
      true -> mark(file, current, halves(Template.render(template, names), removed), key)
    end
  end

  # The two halves are labelled inside the region because a reader cannot
  # otherwise tell which lines to delete from which to keep.
  defp halves(block, removed), do: "#{@half} remove\n#{removed}\n#{@half} add\n#{block}"

  @doc """
  Inserts dependencies into the target's `mix.exs`.

  Delegated to `Capstone.Source.MixExs`, which locates the list structurally. The
  previous implementation matched `defp deps do` with a regex, wrote nothing for
  the other three shapes `mix` accepts, and returned `:ok` — a plugin that
  installed no dependencies and reported success. Dependencies are APPENDED
  where the regex prepended; the old position was an artifact of matching the
  opening bracket, not a decision.

  Raises `Capstone.Source.MixExs.Error` when the list cannot be located. A plugin
  that cannot install its dependencies must fail at install time, not hand back
  a project that does not compile.
  """
  @spec add_deps(Path.t(), [binary()]) :: :ok
  def add_deps(_target, []), do: :ok

  # REVERSED, because `add_dep/2` prepends: applying a recorded [A, B, C] in
  # order would leave [C, B, A]. Reversing reproduces the order the plugin
  # was captured from, which is what the round trip compares.
  def add_deps(target, deps),
    do: update_mix_exs!(target, Enum.reverse(deps), &MixExs.add_dep/2)

  @doc """
  Sets each `{name, commands}` pair in the target's `aliases/0`.

  Creates `aliases/0` and wires it into `project/0` when the project has
  neither, which is every `mix new` project.
  """
  @spec put_aliases(Path.t(), keyword()) :: :ok
  def put_aliases(_target, []), do: :ok

  def put_aliases(target, aliases) do
    update_mix_exs!(target, aliases, fn source, {name, commands} ->
      MixExs.put_alias(source, name, commands)
    end)
  end

  @doc "Sets each `{key, value}` pair in the target's `project/0`."
  @spec put_project_keys(Path.t(), keyword()) :: :ok
  def put_project_keys(_target, []), do: :ok

  def put_project_keys(target, keys) do
    update_mix_exs!(target, keys, fn source, {key, value} ->
      MixExs.put_project_key(source, key, value)
    end)
  end

  defp update_mix_exs!(target, changes, fun) do
    file = Path.join(target, "mix.exs")

    patched =
      Enum.reduce(changes, File.read!(file), fn change, source ->
        case fun.(source, change) do
          {:ok, next} -> next
          {:error, reason} -> raise MixExs.Error, "#{file}: #{inspect(reason)}"
        end
      end)

    File.write!(file, patched)
  end

  defp occurrences(haystack, needle), do: length(String.split(haystack, needle)) - 1

  defp insert_after(file, current, needle, block) do
    # Exactly ONE trailing newline, not all of them: the text after the
    # insertion point already begins with a newline, and trim_trailing/2 would
    # swallow a blank line the hunk deliberately contained.
    replacement = needle <> "\n" <> String.replace_suffix(block, "\n", "")

    File.write!(file, String.replace(current, needle, replacement, global: false))
  end

  defp mark(file, current, block, key) do
    region = "#{marker_prefix(key)}\n#{block}#{@close} capstone: #{key}\n"

    File.write!(file, current <> region)
  end

  defp app_name!(target_dir) do
    file = Path.join(target_dir, "mix.exs")
    {:ok, ast} = file |> File.read!() |> Code.string_to_quoted()

    {_ast, found} =
      Macro.prewalk(ast, nil, fn
        {:app, app} = node, _acc when is_atom(app) -> {node, app}
        node, acc -> {node, acc}
      end)

    case found do
      nil -> raise ArgumentError, "no app: in #{file}"
      app -> Atom.to_string(app)
    end
  end
end
