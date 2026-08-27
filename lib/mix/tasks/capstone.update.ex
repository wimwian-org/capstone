defmodule Mix.Tasks.Capstone.Update do
  @shortdoc "Applies newly-declared plugins to an existing Capstone project"
  @moduledoc """
  Applies whatever plugins `target.exs` newly lists (SDD-adjacent; see
  docs/superpowers/specs/2026-08-26-plugin-ecosystem-design.md).

      mix capstone.update [TARGET]

  `TARGET` defaults to the current directory. Only plugins not already
  recorded in `TARGET`'s `plugin.exs` are applied; nothing already applied is
  ever re-resolved or upgraded.
  """
  use Mix.Task

  alias Capstone.Plugin.Registry
  alias Capstone.Update
  alias Capstone.VersionGuard

  @impl Mix.Task
  def run(argv), do: run(argv, Registry.default_dir())

  @doc """
  `run/1` with the plugin registry directory injected.

  The seam exists for tests: without it every test of this task resolves
  against `Capstone.Plugin.Registry.default_dir/0`, which under `MIX_ENV=test`
  is a symlink to this repository's own checked-in, hex-shipped
  `priv/plugins/` — so a test that seeds a fixture archive seeds it into the
  package.
  """
  @spec run([String.t()], Path.t()) :: :ok
  def run([], registry_dir), do: do_run(".", registry_dir)
  def run([target], registry_dir), do: do_run(target, registry_dir)

  def run(_argv, _registry_dir),
    do: Mix.raise("capstone.update expects at most one target directory")

  defp do_run(target, registry_dir) do
    VersionGuard.verify!()
    {:ok, applied} = Update.run(target, registry_dir)

    case applied do
      [] -> Mix.shell().info("nothing new to apply")
      types -> Mix.shell().info("applied: #{Enum.map_join(types, ", ", &to_string/1)}")
    end
  end
end
