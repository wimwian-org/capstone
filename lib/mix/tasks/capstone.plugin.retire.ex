defmodule Mix.Tasks.Capstone.Plugin.Retire do
  @shortdoc "Retires a plugin archive so future resolutions skip it"
  @moduledoc """
  Retires a plugin archive so future resolutions skip it (SDD-adjacent; see
  docs/superpowers/specs/2026-08-26-plugin-ecosystem-design.md).

      mix capstone.plugin.retire cache-1.20.3-0.1.0-a3f9c21b0e77.tar.gz

  Never deletes the archive — it is kept on disk for provenance and simply
  excluded from `Capstone.Plugin.Registry.resolve!/4`.
  """
  use Mix.Task

  alias Capstone.Plugin.Registry
  alias Capstone.VersionGuard

  @registry "priv/plugins"

  @impl Mix.Task
  def run([filename]) do
    VersionGuard.verify!()

    if not File.regular?(Path.join(@registry, filename)) do
      Mix.raise("#{Path.join(@registry, filename)} does not exist")
    end

    Registry.retire!(filename, @registry)
    Mix.shell().info("retired #{filename}")
  end

  def run(_argv), do: Mix.raise("capstone.plugin.retire expects one archive filename")
end
