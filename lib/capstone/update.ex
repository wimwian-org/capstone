defmodule Capstone.Update do
  @moduledoc """
  Applies whatever plugins a project's `target.exs` newly lists that its
  `plugin.exs` hasn't recorded yet — see
  docs/superpowers/specs/2026-08-26-plugin-ecosystem-design.md.

  Never re-resolves or upgrades an already-recorded plugin, even when a
  better-matching archive now exists for it — that comparison is explicitly
  out of scope, per the design doc's "Explicitly out of scope" section.
  """

  alias Capstone.Config
  alias Capstone.Manifest
  alias Capstone.Plugin.Install
  alias Capstone.Plugin.Remote
  alias Capstone.Root

  @doc """
  Applies every plugin type listed in `target`'s `target.exs` that is not
  already recorded in its `plugin.exs`. Returns the types actually applied,
  in `target.exs`'s own order.

  `sync` is called once per newly-listed type, immediately before that
  type is installed — never once for the whole batch up front, so a later
  type's sync failure never undoes an earlier type's already-completed
  install. Injectable for the same reason `Capstone.New.Bootstrap.run/3`'s
  `effects.sync` is: a test exercising a local, unpublished fixture type
  should not depend on network access.
  """
  @spec run(Path.t(), Path.t(), (atom(), Path.t() -> :ok)) :: {:ok, [atom()]}
  def run(target, registry_dir, sync \\ &Remote.sync!/2) do
    root = Root.new!(target)
    target_exs_path = Root.path(root, "target.exs")

    if File.regular?(target_exs_path) do
      config = Config.read!(target_exs_path)
      already = already_applied(root)

      newly_listed = Enum.filter(config.plugins, &(&1 not in already))

      Enum.each(newly_listed, fn type ->
        sync.(type, registry_dir)
        Install.run(type, target, registry_dir)
      end)

      {:ok, newly_listed}
    else
      {:ok, []}
    end
  end

  defp already_applied(root) do
    manifest_path = Manifest.path(root)

    if File.regular?(manifest_path) do
      root |> Manifest.read!() |> Map.fetch!(:plugins) |> Enum.map(& &1.name)
    else
      []
    end
  end
end
