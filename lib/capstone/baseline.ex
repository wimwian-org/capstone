defmodule Capstone.Baseline do
  @moduledoc """
  Provenance and drift checking for the checked-in generator baselines.

  Every function is pure over a directory — nothing here shells out to a
  generator, so the drift check runs offline on every commit and 100% coverage
  never depends on having phx_new installed.

  This module must NOT share a normaliser with `Capstone.Hash`. They require
  opposite semantics: the manifest hash ignores an added comment (a
  `# credo:disable-for-next-line` must not lock a project out of updates),
  while a comment added to a baseline IS drift.
  """

  alias Capstone.Source

  # Build artefacts, not source. `node_modules` earns its place the same way
  # `deps` and `_build` do: measured, a meta project with its assets installed
  # reported 38,189 of 38,215 added files as installed packages, and derive
  # then failed trying to template a binary out of one.
  #
  # `.valkey_data` is a directory NAME, not a rooted path, deliberately: it is
  # the bind mount `valkey_component`'s own `compose.yaml` writes its RDB
  # snapshot into, so merely running the sidecar the way that component's own
  # README tells you to leaves a BINARY file behind, and unlike `assets`
  # below it has no legitimate meaning as source at any depth — including
  # inside an umbrella sub-app's own component directory, which a rooted
  # path would miss.
  @pruned ~w(.git deps _build node_modules .valkey_data)

  # Build output and the lockfile, pruned by PATH rather than by directory
  # name. `assets` cannot go in @pruned above — at the project root it is the
  # Svelte source tree, and only under priv/static is it Vite's output.
  #
  # `mix.lock` is here for a different reason than the rest: it is real source
  # a project rightly commits, but a COMPONENT that shipped it would overwrite
  # the target's entire dependency resolution. A plugin contributes
  # dependencies through `deps:`; the resolution is the target's own business.
  # `erl_crash.dump` is never source. A crashed VM inside a meta project — a
  # test run with no database, say — would otherwise change that project's
  # recorded hashes and fail the drift check for a reason unrelated to drift.
  #
  # A path that ISN'T listed here or in `@pruned` still can't crash `derive`
  # silently if it turns out to be binary — `Capstone.Plugin.Derive`'s
  # binary guard turns that into an immediate, actionable `Mix.raise`
  # instead. This list is for cases already known to recur, so they're
  # excluded before the drift check or derive ever sees them, rather than
  # raising on every run.
  @pruned_paths ~w(mix.lock erl_crash.dump priv/static/assets/ priv/static/.vite/)

  # Pinned so the tar is byte-reproducible: the archive's filename is its
  # sha256, so unpinned clock values would rename an unchanged baseline on
  # every run and content-addressing would mean nothing.
  @tar_meta [{:atime, 0}, {:mtime, 0}, {:ctime, 0}, {:uid, 0}, {:gid, 0}]
  @secret_keys %{
    "secret_key_base" => "<<SECRET_KEY_BASE>>",
    "signing_salt" => "<<SIGNING_SALT>>"
  }

  @doc """
  Reads the provenance record.

  Not every entry is a generator baseline. `derived_from:` marks one produced
  by applying a plugin — `mix capstone.baseline.compose` — and such an entry
  has no `argv:`, `generator:` or `generator_version:`. A test that drives a
  generator must select entries that carry them rather than iterating all.
  """
  # Keyed by baseline name, not by a fixed pair: entries are added as bases and
  # meta projects are, and every caller here iterates rather than reaching for
  # one key.
  @spec read!(Path.t()) :: %{atom() => map()}
  def read!(path), do: Source.decode!(File.read!(path), path)

  @doc """
  Replaces phx.new's four `crypto:strong_rand_bytes` values with placeholders.

  Anchors on the key name, never on a bare length match: the alphabet is
  unpadded base64, so values contain `+` and `/` and may start with `/`.
  """
  @spec normalise_secrets(binary()) :: binary()
  def normalise_secrets(source) do
    Enum.reduce(@secret_keys, source, fn {key, placeholder}, acc ->
      String.replace(acc, ~r/#{key}: "[^"]*"/, ~s|#{key}: "#{placeholder}"|)
    end)
  end

  @doc "Maps every relative path under `dir` to the sha256 of its normalised bytes."
  @spec tree(Path.t()) :: %{Path.t() => binary()}
  def tree(dir) do
    root = Path.expand(dir)

    root
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.reject(&File.dir?/1)
    |> Enum.map(&Path.relative_to(&1, root))
    |> Enum.reject(&pruned?/1)
    |> Map.new(&{&1, file_hash(Path.join(root, &1))})
  end

  @doc "A single digest over the whole tree."
  @spec digest(Path.t()) :: binary()
  def digest(dir) do
    lines =
      dir
      |> tree()
      |> Enum.sort()
      |> Enum.map_join("\n", fn {path, hash} -> "#{path} #{hash}" end)

    "sha256:" <> hash(lines)
  end

  @doc """
  Recomputes every entry's derived fields from disk.

  `files` and `tree_digest` are recomputed; every other field is passed through
  untouched. `generator_version` above all must never be sourced from the
  running toolchain — it is the pin that makes the toolchain test fail with one
  line on a phx_new bump instead of a 45-file hash diff.

  `:file_count` is dropped: `files` supersedes it and `map_size/1` is exact.

  `archive_sha256` is recorded here rather than in a sidecar file. It is not
  circular: the archive holds only the project's files, so the manifest is not
  an input to its own recorded hash and one pass converges.
  """
  @spec record(%{atom() => map()}) :: %{atom() => map()}
  def record(manifest) do
    Map.new(manifest, fn {key, entry} ->
      recorded =
        entry
        |> Map.delete(:file_count)
        |> Map.put(:files, tree(entry.path))
        |> Map.put(:tree_digest, digest(entry.path))

      {sha, _gzipped} = snapshot(recorded)

      {key, Map.put(recorded, :archive_sha256, sha)}
    end)
  end

  @doc """
  Builds reproducible, uncompressed tar bytes from in-memory members.

  Members are `{name_charlist, contents}` and are sorted here rather than by the
  caller, so member order cannot vary with map iteration.
  """
  @spec tar([{charlist(), binary()}]) :: binary()
  def tar(members) do
    sorted = Enum.sort(members)

    # The scratch name is derived from the members themselves. erl_tar writes
    # through the filesystem, but the ambient-state ban rules out a unique-
    # integer suffix, and a content-derived name is both deterministic and
    # distinct for distinct content — two callers racing here are writing
    # identical bytes by construction. BoundaryGuard scans raw source, so the
    # banned token must not appear even inside this comment.
    key = sorted |> :erlang.term_to_binary() |> hash()
    path = Path.join(System.tmp_dir!(), "capstone-tar-#{key}")

    try do
      {:ok, handle} = :erl_tar.open(String.to_charlist(path), [:write])

      Enum.each(sorted, fn {name, contents} ->
        :erl_tar.add(handle, contents, name, @tar_meta)
      end)

      :erl_tar.close(handle)
      File.read!(path)
    after
      File.rm(path)
    end
  end

  @doc """
  Selects one baseline's archive members.

  Contents come from disk but membership comes from the entry's `files` map,
  never from a fresh wildcard — that is what makes it structurally impossible
  for the archive and the manifest to disagree about the baseline.

  Names are project-relative, identical to the `files` keys, so each archive
  unpacks as a standalone snapshot of that generated project and a member name
  can be looked up in `files` directly.
  """
  @spec members(map()) :: [{charlist(), binary()}]
  def members(entry) do
    for {relative, _hash} <- entry.files do
      {String.to_charlist(relative), File.read!(Path.join(entry.path, relative))}
    end
  end

  @doc """
  Builds one baseline's self-verifying snapshot.

  The `.tar.gz` is an OUTER tar holding two members: `baseline.tar` — the
  project's files — and `baseline.sha256`, its checksum. The checksum sits
  beside the inner tar rather than inside it, which is the only placement that
  terminates: a file recording a tar's hash cannot also be a member of it.

  Returns `{sha, gzipped}` where `sha` is the hex sha256 of the INNER tar.
  """
  @spec snapshot(map()) :: {binary(), binary()}
  def snapshot(entry) do
    inner = entry |> members() |> tar()
    sha = hash(inner)

    outer =
      tar([
        {~c"baseline.tar", inner},
        {~c"baseline.sha256", "#{sha}  baseline.tar\n"}
      ])

    {sha, :zlib.gzip(outer)}
  end

  @doc """
  Names an archive `<type>_<version>_<last 8 of sha>.tar.gz`.

  `type` is the manifest KEY, passed through verbatim rather than checked
  against a closed `otp | api | web` set — `priv/baselines.exs` already carries
  a fourth (`:web_layer`), and a list here would have to be edited in lockstep
  with that file, where forgetting yields a mislabelled archive rather than an
  error.

  `version` is an argument and never read from anywhere here, so this module
  stays a pure function of what it is given — which is also what keeps it clear
  of the ambient-state ban `Capstone.BoundaryGuard` enforces.
  `Mix.Tasks.Capstone.Baseline.Record` supplies it, from the `.version` file that is
  the project's source of truth. That is the version the release tag names, so
  an archive and the release it is attached to agree by construction.

  Only the last 8 characters of the sha: the full digest is recorded as
  `archive_sha256` in the manifest and again inside the archive itself, so the
  filename only has to be short and distinguishing. What the prefix adds is
  legibility — a directory of release assets says which baseline and which
  release each file belongs to without opening any of them.
  """
  @spec archive_name(atom() | binary(), binary(), binary()) :: binary()
  def archive_name(type, version, sha) do
    "#{type}_#{version}_#{String.slice(sha, -8, 8)}.tar.gz"
  end

  defp pruned?(relative) do
    relative |> Path.split() |> Enum.any?(&(&1 in @pruned)) or pruned_path?(relative)
  end

  defp pruned_path?(relative) do
    Enum.any?(@pruned_paths, &(relative == &1 or String.starts_with?(relative, &1)))
  end

  defp file_hash(path) do
    path
    |> File.read!()
    |> normalise_secrets()
    |> hash()
  end

  defp hash(bytes), do: :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)
end
