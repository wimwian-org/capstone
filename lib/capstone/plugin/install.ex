defmodule Capstone.Plugin.Install do
  @moduledoc """
  The one resolve → extract → apply → record → clean-up sequence both
  `mix capstone.new` and `mix capstone.update` use — see
  docs/superpowers/specs/2026-08-26-plugin-ecosystem-design.md.
  """

  alias Capstone.Plugin.Apply
  alias Capstone.Plugin.Registry

  @doc """
  Resolves `type` in `registry_dir` for the running Elixir/Capstone versions,
  applies it to `target`, and records it with a `{:registry, filename}`
  origin. The extraction temp directory is removed whether apply succeeds or
  raises.
  """
  @spec run(atom(), Path.t(), Path.t()) :: {:ok, map()}
  def run(type, target, registry_dir) do
    archive = Registry.resolve!(type, System.version(), capstone_version(), registry_dir)
    tmp = extraction_dir(archive)

    try do
      File.mkdir_p!(tmp)
      extract!(archive, tmp)
      Apply.run(tmp, target, origin: {:registry, Path.basename(archive)})
    after
      File.rm_rf!(tmp)
    end
  end

  # Named from the archive's own (content-derived) filename, never ambient
  # state like randomness or monotonic counters that would break
  # determinism across runs.
  defp extraction_dir(archive) do
    Path.join(System.tmp_dir!(), "capstone_plugin_" <> Path.basename(archive, ".tar.gz"))
  end

  defp extract!(archive, into) do
    :ok =
      :erl_tar.extract(String.to_charlist(archive), [
        :compressed,
        {:cwd, String.to_charlist(into)}
      ])
  end

  defp capstone_version, do: List.to_string(Application.spec(:capstone, :vsn))
end
