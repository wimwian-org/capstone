defmodule Mix.Tasks.Capstone.Plugin.Package do
  # DELIBERATELY no @shortdoc, for the reason given in capstone.check: lib/**
  # ships in the hex package, so this task installs into every consuming
  # project, where it is meaningless (there is no priv/meta/meta_<name> there).
  @moduledoc """
  Packages a derived plugin into `priv/plugins/` (SDD-adjacent; see
  docs/superpowers/specs/2026-08-26-plugin-ecosystem-design.md).

      mix capstone.plugin.package cache

  Reads `priv/meta/meta_<name>/` — written by `mix capstone.plugin.derive` —
  and writes a versioned `.tar.gz` to `priv/plugins/`.

  `<name>` must be a key of `priv/baselines.exs`, the same manifest
  `mix capstone.plugin.derive` reads.
  """
  use Mix.Task

  alias Capstone.Baseline
  alias Capstone.Plugin.Package
  alias Capstone.VersionGuard

  @registry "priv/plugins"
  @baselines "priv/baselines.exs"

  @impl Mix.Task
  def run([name]) do
    VersionGuard.verify!()
    # Argument validation precedes the filesystem work, so a plain typo is
    # answered by the list of names on offer rather than by the absence of a
    # directory that was never going to exist.
    type = plugin_type!(name)
    dir = Path.join("priv/meta", "meta_#{name}")

    if not File.dir?(dir) do
      Mix.raise("#{dir} does not exist; run mix capstone.plugin.derive #{name}")
    end

    {:ok, path} = Package.run(type, dir, @registry)
    Mix.shell().info("wrote #{path}")
  end

  def run(_argv), do: Mix.raise("capstone.plugin.package expects one plugin name")

  # Matched on the PRINTED key rather than by interning the argument, exactly
  # as `mix capstone.plugin.derive` does. `String.to_existing_atom/1` here was
  # reachable only when something else had already interned the type in this
  # BEAM — `:cache` happened to be, `:openapi` and `:prod_image_api` were not,
  # so a standalone `mix capstone.plugin.package openapi` died with a bare
  # ArgumentError. Taking the key the decoded manifest already holds mints no
  # atom from CLI input at all and, unlike a bare existence check, tells a
  # maintainer which names are actually on offer.
  defp plugin_type!(name) do
    @baselines
    |> Baseline.read!()
    |> Enum.find(fn {key, _entry} -> Atom.to_string(key) == name end)
    |> case do
      {key, _entry} ->
        key

      nil ->
        Mix.raise("unknown plugin type #{name}; must be one of the baselines in #{@baselines}")
    end
  end
end
