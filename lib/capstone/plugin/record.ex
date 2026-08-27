defmodule Capstone.Plugin.Record do
  @moduledoc """
  Records an applied plugin in the target's `plugin.exs` (SDD 8.2, R5, R6).

  `Capstone.Plugin.Apply` installs; this records what was installed and with
  which content hashes, so a later update can tell an untouched file from an
  edited one. Nothing else under `lib/` writes a manifest.

  ## Only into a project that declares itself

  `Capstone.Manifest` enforces six top-level keys, four of which describe a
  project the scaffolder generated. Apply deliberately works against ANY
  project — its round trip installs `meta_cache` into a bare copy of
  `baseline_otp` that has no `target.exs` at all — so recording is conditional:

  | Root             | Apply                 | This module           |
  | ------------------ | --------------------- | --------------------- |
  | has `target.exs` | installs              | writes `plugin.exs` |
  | has none           | installs, and says so | does nothing          |

  Inferring the missing fields was rejected: a manifest that asserts an inferred
  `base` is worse than no manifest, because the update flow trusts it. Creating
  a `target.exs` was rejected too — installing a plugin would silently
  convert someone's project into a Capstone project.

  ## What a plugin changed in `mix.exs`, and what is still not hashed

  `deps`, `aliases` and `project` are recorded on the entry. Until they were,
  `Capstone.Plugin.Apply` wrote a plugin's dependencies into the target's
  `mix.exs` and nothing said WHICH plugin had put them there, so an update
  flow could neither attribute a dependency nor notice that a user had since
  hand-edited it.

  They are recorded as DECLARATIONS, not as hashes. `Derive` extracts `mix.exs`
  out of `files` and into these three keys, so `file_entry/3` never sees the
  file and no content hash of `mix.exs` exists in the manifest. That is the
  right shape — `mix.exs` is a file every plugin and the project itself
  writes to, so a whole-file hash would report drift on every unrelated edit —
  but it means drift detection for these three is a structural comparison an
  update flow has to make against the target's CURRENT `mix.exs`, not a hash
  comparison like every other entry. That comparison is D7's work and is not
  written yet.

  ## What is re-read and what is carried across

  `base` and `config_digest` come from the target's CURRENT `target.exs` on
  every write, so the two always describe the same file. `generated_at` is
  MINTED on the first write — when no `plugin.exs` exists yet — and carried
  unchanged from the existing manifest on every write after that: it is a fact
  about the past, and a recorder rewriting it would erase the only record of
  when the project was FIRST RECORDED. For a project the archive generated
  weeks earlier, that first-write instant is when a plugin was first
  applied, not when the project itself was laid down — `generated_at` means
  "first recorded", not "generated", and no better source exists:
  `target.exs` carries no timestamp of its own, while `plugin.exs`
  requires the key. `applied_at` is per plugin and is always this instant.

  `capstone_version` sits in tension with that argument, and deliberately so:
  it is RECOMPUTED on every write, from the running scaffolder's own
  `Application.spec/2`, never carried forward the way `generated_at` is. It
  means "last written by version X", not "the version that generated this
  project" — a project laid down under 1.0.0 and later touched by a plugin
  applied under 1.2.0 shows `capstone_version: "1.2.0"` in its `plugin.exs`,
  same treatment as `applied_at` and unlike `generated_at`.

  `config_digest` is COMPUTED here. `target.exs` carries no such field and
  `Capstone.Manifest` checks it for format only — its moduledoc states that
  nothing produces one until the generator exists. This is that producer, and it
  goes through `Capstone.Hash` rather than a raw sha256 deliberately: a comment
  added to `target.exs` is not a change of intent, and must not read as one
  when the update flow compares digests. `Capstone.Hash.content_hash/2` already
  emits exactly the `"sha256:" <> 64 lowercase hex` the format requires.

  ## Hashes come from `Capstone.Hash`, never `Capstone.Baseline`

  Three normalisers in this repository, three jobs. `Capstone.Hash` treats an
  added comment as NOT a change, because comments are user-owned;
  `Capstone.Baseline` treats one as drift, which is right for a generator
  baseline and wrong here. SDD 4.1 records Fireside reading one added `# note`
  as "diverged, aborting", and a `# credo:disable-for-next-line` must never lock
  a project out of updates.

  The one exception is a file `Capstone.Plugin.Apply` left conflict-marked:
  that file is not the language its name promises, the parser refuses it, and
  `Capstone.Hash.text_hash/1` hashes it as text instead. The marker is read off
  DISK rather than reported by apply, because a second apply short-circuits on
  the marker already being there and would report nothing.

  The check is for the GENERIC marker prefix — `Apply.marker_prefix("")`, the
  same one `mix capstone.check` scans for — not this entry's own key. A marker
  another key left behind still makes the whole file unparseable, and checking
  only this entry's key would fall through to `content_hash/2` and raise after
  every file has already been written, with no manifest to show for it.
  Whichever key wrote a marker, its presence anywhere in the file is what
  matters, never which key.

  This is not a defence against every unparseable file. A target file that was
  already broken before apply ran — the user's own syntax error, or a conflict
  marker left by their own VCS rather than by this module — still raises
  `SyntaxError` from `content_hash/2`, naming the file. That project was
  already uncompilable; recording could not have fixed it, and doing so is out
  of scope here.
  """

  alias Capstone.Clock
  alias Capstone.Config
  alias Capstone.Hash
  alias Capstone.Manifest
  alias Capstone.Plugin.Apply
  alias Capstone.Root
  alias Capstone.Template

  @doc """
  Reports whether `target_dir` declares itself a Capstone project.

  ONE definition, read by `run/4` to decide and by
  `mix capstone.plugin.apply` to report — so the behaviour and the message
  about it cannot drift apart.

  Raises `Capstone.Root.InvalidRootError` if `target_dir` has no `mix.exs` —
  it is not a project directory at all, tracked or otherwise.
  """
  @spec tracked?(Path.t()) :: boolean()
  def tracked?(target_dir),
    do: target_dir |> Root.new!() |> Root.path("target.exs") |> File.regular?()

  @doc """
  Pre-flights the reads `run/4` needs, so a malformed `target.exs` or
  `plugin.exs` raises BEFORE `Capstone.Plugin.Apply` writes a single file.

  A no-op for an untracked target: `tracked?/1` is the same predicate `run/4`
  gates on, so an untracked target takes on no new read and no new failure
  mode. Reused rather than reimplemented, so the two can never drift.
  """
  @spec preflight!(Path.t()) :: :ok
  def preflight!(target_dir) do
    if tracked?(target_dir) do
      target = Root.new!(target_dir)
      Config.read!(Root.path(target, "target.exs"))
      if File.regular?(Manifest.path(target)), do: Manifest.read!(target)
    end

    :ok
  end

  @doc """
  Records `plugin` in `target_dir`'s `plugin.exs`, if it has a `target.exs`.

  `component_dir` becomes the entry's `{:path, _}` origin, made relative because
  a manifest naming one machine's checkout is not portable to another machine or
  to CI (SDD 4.1 defect 13). The base point is the SCAFFOLDER's own working
  directory — where the plugin lives — never the target directory that
  stores the manifest; that is the same base point a project's own
  `target.exs` `plugins:` entry already uses for a `path:` plugin
  (SDD 8.1). A plugin directory outside the working directory stays
  absolute and is refused by `Capstone.Manifest`, which is the correct answer:
  it could not be recorded portably.

  `names` is the triple the files were rendered with, and is what resolves each
  declared path to the one actually on disk.

  `opts[:origin]`, when given, is recorded VERBATIM instead of the computed
  `{:path, _}` — the caller's opinion of where the plugin came from wins.
  `Capstone.Plugin.Apply.run/3` passes `{:registry, filename}` here for a
  plugin applied from a packaged archive's temporary extraction directory,
  where `component_dir` names a directory that is deleted moments later and so
  cannot be the recorded origin. The default is computed LAZILY so an override
  never pays for a `Path.relative_to_cwd/1` call it discards.
  """
  @spec run(Path.t(), Path.t(), map(), Template.names(), keyword()) :: :ok
  def run(component_dir, target_dir, plugin, names, opts \\ []) do
    if tracked?(target_dir) do
      write(component_dir, Root.new!(target_dir), plugin, names, opts)
    else
      :ok
    end
  end

  defp write(component_dir, target, plugin, names, opts) do
    now = Clock.now()

    origin =
      Keyword.get_lazy(opts, :origin, fn -> {:path, Path.relative_to_cwd(component_dir)} end)

    entry = %Manifest.Plugin{
      aliases: Map.get(plugin, :aliases, []),
      applied_at: now,
      deps: Map.get(plugin, :deps, []),
      files: Enum.map(plugin.files, &file_entry(&1, target, names)),
      name: plugin.name,
      origin: origin,
      project: Map.get(plugin, :project, []),
      version: plugin.version
    }

    Manifest.write!(target, put(manifest(target, now), entry))
  end

  # Re-applying REPLACES a plugin's entry rather than appending a second one:
  # `Manifest.encode!/1` rejects duplicate names, so an append-only recorder
  # would fail its own validator on the second run. Position does not matter —
  # `encode!/1` sorts plugins by name.
  defp put(%Manifest{plugins: plugins} = manifest, entry) do
    %{manifest | plugins: [entry | Enum.reject(plugins, &(&1.name == entry.name))]}
  end

  defp manifest(target, now) do
    file = Root.path(target, "target.exs")
    source = File.read!(file)

    fresh = %Manifest{
      base: Config.read_string!(source).base,
      plugins: [],
      config_digest: Hash.content_hash(source, file),
      generated_at: now,
      # Read from Capstone.Manifest rather than written literally, and NOT
      # carried from an existing manifest: a carried value would silently
      # DOWNGRADE a newer file instead of refusing to touch it. Capstone.Manifest
      # still READS every version in its supported list, so an older file
      # decodes and is then rewritten at the current one.
      schema_version: Manifest.schema_version(),
      capstone_version: version()
    }

    carry(fresh, target)
  end

  defp carry(fresh, target) do
    if File.regular?(Manifest.path(target)) do
      previous = Manifest.read!(target)

      %{fresh | plugins: previous.plugins, generated_at: previous.generated_at}
    else
      fresh
    end
  end

  defp file_entry(declared, target, names) do
    {declared_path, mode, key} = shape(declared)
    path = Template.resolve_path(declared_path, names)
    contents = File.read!(Root.path(target, path))

    %Manifest.FileEntry{hash: hash(contents, path, key), key: key, mode: mode, path: path}
  end

  # `mode` is carried through as the plugin declared it, `:manual` included,
  # so the update flow knows which entries a human placed.
  defp shape({path, :sole_owner}), do: {path, :sole_owner, nil}
  defp shape({path, mode, opts}), do: {path, mode, Keyword.fetch!(opts, :key)}

  # No key to check, and none needed: nil only ever reaches here for
  # :sole_owner (see shape/1), and Apply.write_owned/4 overwrites the whole
  # file on every apply, so a :sole_owner entry can never carry a marker some
  # OTHER plugin's :manual mode left behind — there is nothing on disk for
  # a marker check to find.
  defp hash(contents, path, nil), do: Hash.content_hash(contents, path)

  # The GENERIC prefix, not this entry's own key: a marker another key left
  # behind still makes the file unparseable, and dispatching on presence — a
  # fact read off disk — never on whether the bytes happen to parse, is the
  # same discipline `Capstone.Hash.content_hash/2` itself refuses to break.
  defp hash(contents, path, _key) do
    if String.contains?(contents, Apply.marker_prefix("")),
      do: Hash.text_hash(contents),
      else: Hash.content_hash(contents, path)
  end

  # The running scaffolder's own version, from its application spec. Not from
  # the VERSION file: `mix.exs` resolves that against its own directory using a
  # token `Capstone.BoundaryGuard` bans everywhere under `lib/`.
  defp version, do: List.to_string(Application.spec(:capstone, :vsn))
end
