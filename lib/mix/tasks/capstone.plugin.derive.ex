defmodule Mix.Tasks.Capstone.Plugin.Derive do
  @shortdoc "Derives a plugin from a raw working project"
  @moduledoc """
  Derives a plugin from a raw working project (SDD 10).

      mix capstone.plugin.derive cache

  Reads the named entry from `priv/baselines.exs` — its raw project `path`, the
  baseline it is `derived_from` and the `names` its placeholders replace — and
  writes the templated plugin to `priv/meta/meta_<name>/`.

  A directory whose name starts with `meta_` carries placeholders; one that does
  not is a raw project. `cache_component` in, `meta_cache` out.
  """
  use Mix.Task

  alias Capstone.Baseline
  alias Capstone.Plugin.Derive
  alias Capstone.VersionGuard

  @manifest "priv/baselines.exs"

  # `@recursive true` -- see `mix capstone.baseline.record` for the measurement.
  # A plain Mix task run at the umbrella root gets the ROOT's cwd, where the
  # bare "priv/baselines.exs" below does not exist; recursive, it runs once per
  # app with that app's directory as cwd. It therefore also runs in
  # apps/capstone_new, which carries no payload, so a missing manifest is a
  # NO-OP rather than a raise.
  @recursive true

  @impl Mix.Task
  def run([name]) do
    VersionGuard.verify!()
    if File.regular?(@manifest), do: derive(name), else: :ok
  end

  def run(_argv), do: Mix.raise("capstone.plugin.derive expects one plugin name")

  defp derive(name) do
    manifest = Baseline.read!(@manifest)
    {key, entry} = fetch_entry!(manifest, name)
    baseline = fetch_baseline!(manifest, entry, name)
    out = Path.join("priv/meta", "meta_#{name}")

    opts = [
      name: key,
      baseline: baseline.path,
      meta: entry.path,
      names: entry.names,
      out: out
    ]

    case Derive.run(opts) do
      {:ok, plugin} ->
        Mix.shell().info("wrote #{out}/manifest.exs")
        Mix.shell().info("  files: #{length(plugin.files)}, deps: #{length(plugin.deps)}")

      {:error, {:unrepresentable_deletions, paths}} ->
        Mix.raise("""
        #{name} deletes baseline files, which SDD 7.3 has no ownership mode for:

          #{Enum.join(paths, "\n  ")}
        """)

      {:error, {:unrepresentable_binary_additions, paths}} ->
        Mix.raise("""
        #{name} adds binary file(s) that can't be templated as plugin source:

          #{Enum.join(paths, "\n  ")}

        If this is real plugin content, Derive has no way to represent a
        binary file as templated `:sole_owner` source -- it needs a different
        ownership approach.

        If this is NOT real content (a build artifact, a container's runtime
        data), delete it and re-run, or -- if it will keep reappearing
        whenever the raw component's own tooling runs -- add its path to
        `Capstone.Baseline`'s `@pruned_paths` so it's excluded permanently.
        """)
    end
  end

  # Matched on the printed key rather than by interning the argument: the atom
  # is already in the table once the manifest is decoded, and comparing strings
  # needs no conversion at all.
  defp fetch_entry!(manifest, name) do
    Enum.find(manifest, fn {key, _entry} -> Atom.to_string(key) == name end) ||
      Mix.raise("#{name} has no entry in #{@manifest}")
  end

  defp fetch_baseline!(manifest, entry, name) do
    case entry do
      %{derived_from: from} -> Map.fetch!(manifest, from)
      _no_baseline -> Mix.raise("#{name} has no derived_from: in #{@manifest}")
    end
  end
end
