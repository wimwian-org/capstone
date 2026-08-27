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

  Raises `Mix.Error`, naming `type` and both versions, when nothing survives.
  """
  @spec resolve!(atom(), String.t(), String.t(), Path.t()) :: Path.t()
  def resolve!(type, elixir_version, capstone_version, registry_dir) do
    retired = retired(registry_dir)

    registry_dir
    |> archives()
    |> Enum.filter(fn archive ->
      archive.type == Atom.to_string(type) && elixir_compatible?(archive.elixir, elixir_version)
    end)
    |> Enum.reject(&(&1.filename in retired))
    |> Enum.filter(&capstone_le?(&1.capstone, capstone_version))
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

  defp parse(path) do
    basename = Path.basename(path)

    with true <- String.ends_with?(basename, ".tar.gz"),
         stem = String.replace_suffix(basename, ".tar.gz", ""),
         [type, elixir, capstone, sha] <- String.split(stem, "-") do
      %{type: type, elixir: elixir, capstone: capstone, sha: sha, filename: basename, path: path}
    else
      _unparseable -> nil
    end
  end

  defp elixir_compatible?(archive_version, running_version) do
    major_minor(archive_version) == major_minor(running_version)
  end

  defp major_minor(version) do
    %Version{major: major, minor: minor} = Version.parse!(version)
    {major, minor}
  end

  defp capstone_le?(archive_version, running_version) do
    version_key(archive_version) <= version_key(running_version)
  end

  defp version_key(version) do
    %Version{major: major, minor: minor, patch: patch} = Version.parse!(version)
    {major, minor, patch}
  end

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
