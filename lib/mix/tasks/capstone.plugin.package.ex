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
  """
  use Mix.Task

  alias Capstone.Plugin.Package
  alias Capstone.VersionGuard

  @registry "priv/plugins"

  @impl Mix.Task
  def run([name]) do
    VersionGuard.verify!()
    dir = Path.join("priv/meta", "meta_#{name}")

    if not File.dir?(dir) do
      Mix.raise("#{dir} does not exist; run mix capstone.plugin.derive #{name}")
    end

    {:ok, path} = Package.run(String.to_existing_atom(name), dir, @registry)
    Mix.shell().info("wrote #{path}")
  end

  def run(_argv), do: Mix.raise("capstone.plugin.package expects one plugin name")
end
