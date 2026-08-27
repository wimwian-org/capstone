defmodule Capstone.Manifest do
  @moduledoc """
  Reads and writes `plugin.exs` — the generated lock file (SDD 8.2).

  Reading is completely independent of the target's `mix.exs`, its deps, its
  `_build`, and of Mix being started at all. That is the one property worth
  keeping from Fireside, because `mix capstone.update` must run against a
  project that may not compile — asserted against a target whose `mix.exs` has
  a syntax error and one that raises `UndefinedFunctionError` at load.

  `read!/1` and `write!/2` take a `%Capstone.Root{}` and never move the
  process to another directory. Reading would work either way, but F4's
  mechanism is live: once the working directory moves, Mix's build-path and
  compile-path accessors re-expand a relative `_build` and return a directory
  that does not exist, while its current-project accessor stays pinned to the
  scaffolder. The leak is asymmetric, which is why spot-checking the project
  accessor afterwards concludes nothing leaked.

  The prose above is deliberately written without the literal tokens
  `Capstone.BoundaryGuard` bans: the guard is a substring scan over the whole
  file, comments and docs included, so naming those accessors the obvious way
  would make `lib/` fail its own boundary test.

  No timestamp is minted here — `generated_at` and `applied_at` are
  caller-supplied ISO8601-Z strings (D8).

  ## Ordering

  `Capstone.Source` owns map KEY order; list order is this module's. `encode!/1`
  sorts plugins by `name` and each plugin's files by `path`, *after*
  rejecting duplicate plugin names — the uniqueness check has to precede
  the sort, or two plugins sharing a name would sort into an arbitrary
  order instead of raising.

  `decode!/2` does not re-sort. A file this module wrote is already canonical,
  and a second sorting call site would be a second place for the rule to
  drift; the round-trip test asserts `read!/1` returns what `write!/2` was
  given, which is what makes that safe.

  ## Deliberate asymmetries

    * `config_digest` and every file `hash` are checked for FORMAT only.
      Nothing here derives a digest from anything: nothing produces one until
      the generator exists, so a function to compute one would be a guess at a
      caller that does not exist.
    * `schema_version` is validated on decode and not on encode. The only
      producers of a `%Capstone.Manifest{}` are `decode!/2`, which validates
      it, and the generator, which sets the constant — so an encode-side check
      would have no file to name in its message and no caller to reach it.
    * Errors raised while decoding name the file; errors raised from
      `encode!/1` do not. `validate!/1` is shared by both paths, and
      `encode!/1` has no file to name.
  """

  alias Capstone.Manifest.Plugin
  alias Capstone.Root
  alias Capstone.Source

  @filename "plugin.exs"
  # 2 is what this version WRITES; 1 stays readable on purpose. A v1 file is
  # either one SvEx wrote -- in which case `validate_keys!/2` refuses it by
  # naming the renamed key, which is a better error than "schema_version 1 is
  # not supported" -- or one an older Capstone wrote, which decodes unchanged.
  # The bump itself is not cosmetic: `sv_ex_version` became `capstone_version`,
  # and a required key changing name is a file-format change.
  @schema_versions [1, 2]
  @schema_version 2

  # Keys SvEx wrote and Capstone renamed. Listing them turns a confusing
  # "unknown key" into an answer. There is deliberately no migration: a project
  # holding an sv_ex plugin.exs depends on a hex package called `sv_ex`, which
  # still exists and still reads its own files.
  @renamed %{sv_ex_version: :capstone_version}
  # Repeated here rather than read from `Capstone.Config`, deliberately: this
  # module must decode a manifest in a project that does not compile and whose
  # `target.exs` may be unreadable, so it depends on nothing outside itself.
  # `Capstone.ManifestTest` is what keeps the two lists in step — a base added
  # to one and not the other makes a project generatable but unrecordable.
  @bases [:otp, :api, :web]
  @top_keys [
    :base,
    :plugins,
    :config_digest,
    :generated_at,
    :schema_version,
    :capstone_version
  ]
  @digest_format ~r/\Asha256:[0-9a-f]{64}\z/

  @enforce_keys @top_keys
  defstruct @top_keys

  @type t :: %__MODULE__{
          base: :otp | :api | :web,
          plugins: [Plugin.t()],
          config_digest: String.t(),
          generated_at: String.t(),
          # The literal union rather than `pos_integer()`: it is the same list
          # `@schema_versions` validates against, and dialyzer is what notices
          # when the two stop agreeing -- it did, on the commit that bumped the
          # written version to 2 and left this at 1.
          schema_version: 1 | 2,
          capstone_version: String.t()
        }

  @doc """
  The `schema_version` this version of Capstone writes into a new `plugin.exs`.
  """
  @spec schema_version() :: pos_integer()
  def schema_version, do: @schema_version

  @doc """
  The absolute path to `target`'s `plugin.exs`.

  There is no `filename/0` beside it, for the reason `Capstone.Config.path/1`
  gives: a public accessor over a module attribute has no caller that `path/1`
  does not serve better.
  """
  @spec path(Root.t()) :: Path.t()
  def path(target), do: Root.path(target, @filename)

  @doc """
  Reads and validates `target`'s `plugin.exs`.

  Raises `File.Error` if the file is absent, `Capstone.Source.DecodeError` if it
  is not plain data, `SyntaxError`, `TokenMissingError` or
  `MismatchedDelimiterError` if it does not parse at all, and
  `Capstone.Manifest.InvalidError` if it is plain data of the wrong shape. The
  target's `mix.exs` is never consulted, so this works against a project that
  does not compile.
  """
  @spec read!(Root.t()) :: t()
  def read!(target) do
    file = path(target)
    file |> File.read!() |> decode!(file)
  end

  @doc "Validates `manifest` and writes it to `target`'s `plugin.exs`."
  @spec write!(Root.t(), t()) :: :ok
  def write!(target, %__MODULE__{} = manifest) do
    File.write!(path(target), encode!(manifest))
  end

  @doc "Validates a manifest and encodes it to deterministic `.exs` bytes."
  @spec encode!(t()) :: binary()
  def encode!(%__MODULE__{} = manifest) do
    manifest
    |> validate!()
    |> sort()
    |> to_data()
    |> Source.encode!()
  end

  @doc """
  Validates already-read `plugin.exs` source. `file` names it in errors only.
  """
  @spec decode!(binary(), Path.t()) :: t()
  def decode!(source, file) do
    map = Source.decode!(source, file)
    validate_keys!(map, file)

    validate!(%__MODULE__{
      base: fetch!(map, :base, file),
      plugins: Enum.map(fetch!(map, :plugins, file), &Plugin.from_data!(&1, file)),
      config_digest: fetch!(map, :config_digest, file),
      generated_at: fetch!(map, :generated_at, file),
      schema_version: validate_schema_version!(fetch!(map, :schema_version, file), file),
      capstone_version: fetch!(map, :capstone_version, file)
    })
  end

  # A required key that is absent raises the same exception a required key
  # holding the wrong value does — `Capstone.Config` makes the same choice for
  # `target.exs`, and one hand editing the other file deserves one error class.
  @doc false
  def fetch!(map, key, file) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> invalid!("#{file}: #{key} is required")
    end
  end

  # Specced for the dialyzer reason `bad_timestamp!/2` is.
  @doc false
  @spec invalid!(String.t()) :: no_return()
  def invalid!(message), do: raise(__MODULE__.InvalidError, message: message)

  @doc false
  def validate_digest!(digest, field) when is_binary(digest) do
    if digest =~ @digest_format,
      do: :ok,
      else: invalid!("#{field} must match sha256:<64 lowercase hex>, got: #{digest}")
  end

  def validate_digest!(other, field) do
    invalid!("#{field} must be a sha256: string, got: #{inspect(other)}")
  end

  @doc false
  def validate_timestamp!(value, field) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, 0} -> validate_utc_spelling!(datetime, value, field)
      _other -> bad_timestamp!(value, field)
    end
  end

  def validate_timestamp!(other, field), do: bad_timestamp!(other, field)

  defp validate_keys!(map, file) do
    case Enum.sort(Map.keys(map)) -- @top_keys do
      [] -> :ok
      extra -> invalid!(unknown_keys_message(file, extra))
    end
  end

  defp unknown_keys_message(file, extra) do
    case Enum.filter(extra, &is_map_key(@renamed, &1)) do
      [] ->
        "#{file}: unknown key(s): #{inspect(extra)}"

      renamed ->
        detail =
          Enum.map_join(renamed, ", ", &"#{&1} was renamed to #{Map.fetch!(@renamed, &1)}")

        "#{file}: #{detail}. There is deliberately no migration: a project " <>
          "holding an sv_ex plugin.exs depends on a hex package called " <>
          "`sv_ex`, which still exists and still reads its own files."
    end
  end

  defp validate_schema_version!(version, _file) when version in @schema_versions, do: version

  defp validate_schema_version!(other, file) do
    invalid!(
      "#{file}: schema_version #{inspect(other)} is not supported; " <>
        "supported: #{inspect(@schema_versions)}"
    )
  end

  defp validate!(%__MODULE__{} = manifest) do
    validate_base!(manifest.base)
    validate_digest!(manifest.config_digest, "config_digest")
    validate_timestamp!(manifest.generated_at, "generated_at")
    validate_unique_names!(manifest.plugins)
    Enum.each(manifest.plugins, &Plugin.validate!/1)
    manifest
  end

  defp validate_base!(base) when base in @bases, do: :ok

  defp validate_base!(other),
    do: invalid!("base must be one of #{inspect(@bases)}, got: #{inspect(other)}")

  defp validate_unique_names!(plugins) do
    names = Enum.map(plugins, & &1.name)
    duplicates = names -- Enum.uniq(names)

    if duplicates == [],
      do: :ok,
      else: invalid!("duplicate plugin names: #{inspect(duplicates)}")
  end

  # An offset-zero timestamp spelled `+00:00` parses, but writing it back would
  # not reproduce the caller's bytes, so it is not a value this format accepts.
  defp validate_utc_spelling!(datetime, value, field) do
    if DateTime.to_iso8601(datetime) == value, do: :ok, else: bad_timestamp!(value, field)
  end

  # The spec is load-bearing, not decoration: dialyzer reports "has no local
  # return" for a private function that only ever raises INDIRECTLY, and
  # declaring the return type is what says that is the intent rather than a bug.
  @spec bad_timestamp!(term(), String.t()) :: no_return()
  defp bad_timestamp!(value, field) do
    invalid!("#{field} must be an ISO8601 UTC string, got: #{inspect(value)}")
  end

  # Private: ordering is an encoding concern with exactly one caller.
  defp sort(%__MODULE__{plugins: plugins} = manifest) do
    %{manifest | plugins: plugins |> Enum.sort_by(& &1.name) |> Enum.map(&sort_files/1)}
  end

  defp sort_files(plugin) do
    %{plugin | files: Enum.sort_by(plugin.files, & &1.path)}
  end

  defp to_data(%__MODULE__{} = manifest) do
    manifest
    |> Map.from_struct()
    |> Map.update!(:plugins, fn plugins ->
      Enum.map(plugins, &Plugin.to_data/1)
    end)
  end
end

defmodule Capstone.Manifest.Plugin do
  @moduledoc """
  One plugin's entry in `plugin.exs` (SDD 8.2): what it is, which version
  of it was applied, where that version came from, when it was applied, and
  every file it owns or contributes to.

  `origin` is `{:hex, name, version}` or `{:path, relative}`. An ABSOLUTE path
  is rejected: a manifest naming one machine's checkout is not portable to
  another machine or to CI, which is SDD 4.1 defect 13.

  `deps`, `aliases` and `project` record what the plugin changed in the
  TARGET's `mix.exs`. They are what lets an update flow attribute a dependency
  to the plugin that installed it, and notice that a user has since
  hand-edited it — without them, apply wrote into `mix.exs` and nothing said
  who had. All three default to `[]` and are OMITTED from the encoded entry
  when empty, so a manifest written before they existed still decodes and a
  plugin that changes nothing gains no keys.

  There is no cross-plugin conflict check here — two plugins claiming
  the same file is SDD 7.3 policy, not this file's format, and the MVP
  produces no plugin for it to be wrong about.
  """

  alias Capstone.Manifest
  alias Capstone.Manifest.FileEntry

  @enforce_keys [:applied_at, :files, :name, :origin, :version]
  defstruct [
    :applied_at,
    :files,
    :name,
    :origin,
    :version,
    aliases: [],
    deps: [],
    project: []
  ]

  @type origin :: {:hex, String.t(), String.t()} | {:path, Path.t()}

  @type t :: %__MODULE__{
          aliases: keyword(),
          applied_at: String.t(),
          deps: [String.t()],
          files: [FileEntry.t()],
          name: atom(),
          origin: origin(),
          project: keyword(),
          version: String.t()
        }

  @doc false
  def validate!(%__MODULE__{} = plugin) do
    validate_version!(plugin.version)
    validate_origin!(plugin.origin)
    Manifest.validate_timestamp!(plugin.applied_at, "applied_at")
    Enum.each(plugin.files, &FileEntry.validate!/1)
  end

  @doc false
  def from_data!(data, file) do
    %__MODULE__{
      applied_at: Manifest.fetch!(data, :applied_at, file),
      files: Enum.map(Manifest.fetch!(data, :files, file), &FileEntry.from_data!(&1, file)),
      name: Manifest.fetch!(data, :name, file),
      origin: Manifest.fetch!(data, :origin, file),
      version: Manifest.fetch!(data, :version, file),
      # Map.get/3, not fetch!/2: a manifest written before these keys existed
      # is still a valid manifest, and refusing it would lock those projects
      # out of every future update.
      aliases: Map.get(data, :aliases, []),
      deps: Map.get(data, :deps, []),
      project: Map.get(data, :project, [])
    }
  end

  # Empty keys are OMITTED rather than written as `[]`, the same treatment a
  # nil FileEntry key gets and for the same reason: the bytes must match SDD
  # 8.2, and a plugin that changed nothing in mix.exs says so by silence.
  @doc false
  def to_data(%__MODULE__{} = plugin) do
    %{
      applied_at: plugin.applied_at,
      files: Enum.map(plugin.files, &FileEntry.to_data/1),
      name: plugin.name,
      origin: plugin.origin,
      version: plugin.version
    }
    |> put_unless_empty(:aliases, plugin.aliases)
    |> put_unless_empty(:deps, plugin.deps)
    |> put_unless_empty(:project, plugin.project)
  end

  defp put_unless_empty(data, _key, []), do: data
  defp put_unless_empty(data, key, value), do: Map.put(data, key, value)

  # The guard is what makes a numeric version an InvalidError like every other
  # bad field: `Version.parse/1` raises FunctionClauseError on a non-binary.
  defp validate_version!(version) when is_binary(version) do
    case Version.parse(version) do
      {:ok, _parsed} -> :ok
      :error -> bad_version!(version)
    end
  end

  defp validate_version!(other), do: bad_version!(other)

  # Specced for the dialyzer reason `bad_timestamp!/2` in the parent module is.
  @spec bad_version!(term()) :: no_return()
  defp bad_version!(version) do
    Manifest.invalid!("version must be semver, got: #{inspect(version)}")
  end

  defp validate_origin!({:hex, name, version}) when is_binary(name) and is_binary(version),
    do: :ok

  # Same shape of guard, same reason: `Path.type/1` raises FunctionClauseError
  # on a non-binary.
  defp validate_origin!({:path, relative}) when is_binary(relative) do
    if Path.type(relative) == :relative,
      do: :ok,
      else: Manifest.invalid!("origin path must be relative, got the absolute #{relative}")
  end

  defp validate_origin!(other) do
    Manifest.invalid!(
      "origin must be {:hex, name, version} or {:path, relative}, got: #{inspect(other)}"
    )
  end
end

defmodule Capstone.Manifest.FileEntry do
  @moduledoc """
  One file a plugin owns or contributes to (SDD 7.3).

  `mode` and `key` are exclusive. `:contributes` names one block inside a file
  the plugin shares with others, and `:manual` names a hunk that cannot be
  appended safely and is applied as conflict markers instead. Both are
  positional inside a file someone else owns, so both REQUIRE a `key`.
  `:sole_owner` and `:seed` take the whole file and must carry none. A nil key
  is omitted from the encoded entry rather than written as `key: nil`, so the
  bytes match SDD 8.2 exactly.

  `:manual` extends SDD 7.3's three modes. It is not a phantom class like
  `:overwritable`: apply acts on it by writing markers and `mix capstone.check`
  acts on it by failing while one remains.

  There is no `:overwritable` mode. It is SDD 4.1 defect 5/6 — a mode nothing
  downstream can act on — and it appears here only as a value the last clause
  of `validate!/1` rejects, so it can never become a phantom class.
  """

  alias Capstone.Manifest

  @enforce_keys [:hash, :mode, :path]
  defstruct [:hash, :key, :mode, :path]

  @type mode :: :sole_owner | :contributes | :seed | :manual
  @type t :: %__MODULE__{hash: String.t(), key: atom() | nil, mode: mode(), path: String.t()}

  @modes [:sole_owner, :contributes, :seed, :manual]
  @keyed [:contributes, :manual]

  @doc false
  def validate!(%__MODULE__{mode: mode, key: nil, path: path}) when mode in @keyed do
    Manifest.invalid!("#{path}: mode #{inspect(mode)} requires a :key")
  end

  def validate!(%__MODULE__{mode: mode, key: key, path: path})
      when mode not in @keyed and not is_nil(key) do
    Manifest.invalid!("#{path}: mode #{inspect(mode)} must not carry a :key")
  end

  def validate!(%__MODULE__{mode: mode, path: path} = entry) when mode in @modes do
    Manifest.validate_digest!(entry.hash, "#{path} hash")
  end

  def validate!(%__MODULE__{mode: other, path: path}) do
    Manifest.invalid!("#{path}: mode must be one of #{inspect(@modes)}, got: #{inspect(other)}")
  end

  @doc false
  def from_data!(data, file) do
    %__MODULE__{
      hash: Manifest.fetch!(data, :hash, file),
      key: Map.get(data, :key),
      mode: Manifest.fetch!(data, :mode, file),
      path: Manifest.fetch!(data, :path, file)
    }
  end

  # Hand-written, NOT Map.from_struct/1: a nil :key must be OMITTED, not
  # encoded as `key: nil`, so the bytes match SDD 8.2 exactly.
  @doc false
  def to_data(%__MODULE__{key: nil} = entry) do
    %{hash: entry.hash, mode: entry.mode, path: entry.path}
  end

  def to_data(%__MODULE__{} = entry) do
    %{hash: entry.hash, key: entry.key, mode: entry.mode, path: entry.path}
  end
end

defmodule Capstone.Manifest.InvalidError do
  @moduledoc """
  Raised when `plugin.exs` is plain data of the wrong shape — a missing or
  unknown key, an unsupported `schema_version`, or a field whose value is
  outside its domain.
  """
  defexception [:message]
end
