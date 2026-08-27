defmodule Capstone.Plugin.Registry do
  @moduledoc """
  Resolves a plugin type + the running Elixir/Capstone versions to one
  concrete archive under a plugin registry directory — see
  docs/superpowers/specs/2026-08-26-plugin-ecosystem-design.md.
  """

  alias Capstone.Source

  @doc "The real registry directory: this package's own shipped `priv/plugins/`."
  @spec default_dir() :: Path.t()
  def default_dir, do: Application.app_dir(:capstone, "priv/plugins")

  @doc """
  Resolves `type` to the best matching, non-retired archive in `registry_dir`.

  Filters to `type` matches, then to archives whose Elixir segment shares
  major.minor with `elixir_version`, drops retired filenames, drops any whose
  capstone segment exceeds `capstone_version`, then picks the highest
  surviving capstone segment (ties broken by the sha, purely so this stays a
  pure function of its inputs and the directory listing).

  A filename that does not parse — wrong segment count, or a segment that is
  not a version — is reported with `Mix.shell().info/1` and skipped, never
  raised on.

  Raises `Mix.Error`, naming `type` and both versions, when nothing survives.
  """
  @spec resolve!(atom(), String.t(), String.t(), Path.t()) :: Path.t()
  def resolve!(type, elixir_version, capstone_version, registry_dir) do
    retired = retired(registry_dir)
    # The BANG form is right here and only here: these two are the caller's own
    # `System.version()` and `Application.spec(:capstone, :vsn)`, so an
    # unparseable one is a broken VM rather than a stray file on disk. Every
    # version read off a FILENAME goes through `parse/1`'s non-raising form.
    running_elixir = Version.parse!(elixir_version)
    running_capstone = Version.parse!(capstone_version)

    registry_dir
    |> archives()
    |> Enum.filter(fn archive ->
      archive.type == Atom.to_string(type) &&
        major_minor(archive.elixir) == major_minor(running_elixir)
    end)
    |> Enum.reject(&(&1.filename in retired))
    |> Enum.filter(&(Version.compare(&1.capstone, running_capstone) != :gt))
    |> pick!(type, elixir_version, capstone_version)
  end

  defp pick!([], type, elixir_version, capstone_version) do
    Mix.raise(
      "no plugin archive for #{inspect(type)} matches Elixir #{elixir_version} " <>
        "(major.minor) at capstone <= #{capstone_version}"
    )
  end

  defp pick!(candidates, _type, _elixir_version, _capstone_version) do
    candidates
    |> Enum.max_by(&{version_key(&1.capstone), &1.sha})
    |> Map.fetch!(:path)
  end

  defp archives(registry_dir) do
    registry_dir
    |> Path.join("*.tar.gz")
    |> Path.wildcard()
    |> Enum.map(&parse/1)
    |> Enum.filter(& &1)
  end

  # TOTAL, and that is the whole point: both version segments are parsed HERE,
  # with the non-raising `Version.parse/1`, so a wrong segment count and a
  # right-count-wrong-content name (`cache-notaversion-0.1.0-....tar.gz`) take
  # the identical `nil` path. Parsing them downstream instead let one stray
  # file raise `Version.InvalidVersionError` and break resolution for every
  # archive of that type, including the ones that would have matched — which
  # the spec forbids outright: "one stray file must not break every
  # resolution."
  defp parse(path) do
    basename = Path.basename(path)

    with true <- String.ends_with?(basename, ".tar.gz"),
         stem = String.replace_suffix(basename, ".tar.gz", ""),
         [type, elixir, capstone, sha] <- String.split(stem, "-"),
         {:ok, elixir_version} <- Version.parse(elixir),
         {:ok, capstone_version} <- Version.parse(capstone) do
      %{
        type: type,
        elixir: elixir_version,
        capstone: capstone_version,
        sha: sha,
        filename: basename,
        path: path
      }
    else
      _unparseable ->
        Mix.shell().info("skipping #{basename}: not a parseable plugin archive name")
        nil
    end
  end

  defp major_minor(%Version{major: major, minor: minor}), do: {major, minor}

  defp version_key(%Version{major: major, minor: minor, patch: patch}), do: {major, minor, patch}

  @doc """
  Retires `filename` in `registry_dir`'s `retired.exs`, creating the ledger if
  it does not exist yet. Idempotent: retiring an already-retired filename
  changes nothing.
  """
  @spec retire!(String.t(), Path.t()) :: :ok
  def retire!(filename, registry_dir) do
    file = Path.join(registry_dir, "retired.exs")
    current = retired(registry_dir)

    if filename in current do
      :ok
    else
      File.write!(file, Source.encode!(%{retired: Enum.sort([filename | current])}))
    end
  end

  defp retired(registry_dir) do
    file = Path.join(registry_dir, "retired.exs")

    if File.regular?(file) do
      file |> File.read!() |> Source.decode!(file) |> Map.get(:retired, [])
    else
      []
    end
  end
end
