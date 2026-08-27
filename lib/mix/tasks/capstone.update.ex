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
  alias Capstone.Plugin.Remote
  alias Capstone.Update
  alias Capstone.VersionGuard

  @impl Mix.Task
  def run(argv), do: run(argv, Registry.default_dir())

  @doc """
  `run/1` with the plugin registry directory (and, for tests, the sync
  effect) injected.

  The registry-dir seam exists so a test never resolves against
  `Capstone.Plugin.Registry.default_dir/0` — the real, machine-global OS
  cache directory, shared across every project using `capstone` on this
  machine and across test runs. The sync seam exists for the same reason:
  without it, every test that seeds a *local* fixture archive would still
  reach out to the real GitHub release listing for that (never actually
  published) type.
  """
  @spec run([String.t()], Path.t(), (atom(), Path.t() -> :ok)) :: :ok
  def run(argv, registry_dir, sync \\ &Remote.sync!/2)
  def run([], registry_dir, sync), do: do_run(".", registry_dir, sync)
  def run([target], registry_dir, sync), do: do_run(target, registry_dir, sync)

  def run(_argv, _registry_dir, _sync),
    do: Mix.raise("capstone.update expects at most one target directory")

  defp do_run(target, registry_dir, sync) do
    VersionGuard.verify!()
    {:ok, applied} = Update.run(target, registry_dir, sync)

    case applied do
      [] -> Mix.shell().info("nothing new to apply")
      types -> Mix.shell().info("applied: #{Enum.map_join(types, ", ", &to_string/1)}")
    end
  end
end
