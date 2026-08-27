defmodule Capstone.Plugin.Package do
  @moduledoc """
  Packages a derived plugin directory (what `mix capstone.plugin.derive`
  writes to `priv/meta/meta_<name>/`) into a versioned, content-addressed
  `.tar.gz` — see
  docs/superpowers/specs/2026-08-26-plugin-ecosystem-design.md.

  Never re-derives: this module only reads what `Capstone.Plugin.Derive`
  already wrote and packages it byte-for-byte.
  """

  @doc """
  Packages the plugin directory `dir`, named `type`, into `registry_dir`.

  Returns the path to the written archive. Two runs over identical `dir`
  content produce a byte-identical archive and therefore the same filename —
  the sha segment is a plain SHA-256 over the deterministic tar bytes, not
  `Capstone.Hash`'s comment-insensitive normalisation: a package's identity
  must reflect the exact bytes it ships.
  """
  @spec run(atom(), Path.t(), Path.t()) :: {:ok, Path.t()}
  def run(type, dir, registry_dir) do
    tar = dir |> collect() |> build_tar()
    sha = tar |> sha256() |> binary_part(0, 12)
    filename = "#{type}-#{System.version()}-#{capstone_version()}-#{sha}.tar.gz"
    path = Path.join(registry_dir, filename)

    File.mkdir_p!(registry_dir)
    File.write!(path, :zlib.gzip(tar))

    {:ok, path}
  end

  defp collect(dir) do
    dir
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&{Path.relative_to(&1, dir), File.read!(&1)})
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp build_tar(entries) do
    tmp = tar_scratch_path(entries)
    {:ok, tar} = :erl_tar.open(String.to_charlist(tmp), [:write])

    Enum.each(entries, fn {relative, content} ->
      :ok = :erl_tar.add(tar, {String.to_charlist(relative), content}, mtime: 0, uid: 0, gid: 0)
    end)

    :ok = :erl_tar.close(tar)
    bytes = File.read!(tmp)
    File.rm!(tmp)
    bytes
  end

  # Deterministic scratch name derived from the entries themselves — never
  # ambient state like randomness or monotonic counters that would break
  # determinism across runs.
  defp tar_scratch_path(entries) do
    name = entries |> sha256() |> binary_part(0, 16)
    Path.join(System.tmp_dir!(), "capstone_pkg_#{name}.tar")
  end

  defp sha256(term) when is_binary(term), do: hex(:crypto.hash(:sha256, term))
  defp sha256(entries), do: hex(:crypto.hash(:sha256, :erlang.term_to_binary(entries)))

  defp hex(digest), do: Base.encode16(digest, case: :lower)

  defp capstone_version, do: List.to_string(Application.spec(:capstone, :vsn))
end
