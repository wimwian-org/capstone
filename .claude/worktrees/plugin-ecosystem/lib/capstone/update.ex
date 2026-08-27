defmodule Capstone.Update do
  @moduledoc """
  Applies whatever plugins a project's `target.exs` newly lists that its
  `plugin.exs` hasn't recorded yet — see
  docs/superpowers/specs/2026-08-26-plugin-ecosystem-design.md.

  Never re-resolves or upgrades an already-recorded plugin, even when a
  better-matching archive now exists for it — that comparison is explicitly
  out of scope here, the same boundary `Capstone.Plugin.Record`'s own
  moduledoc already documents as unwritten.
  """

  alias Capstone.Config
  alias Capstone.Manifest
  alias Capstone.Plugin.Install
  alias Capstone.Root

  @doc """
  Applies every plugin type listed in `target`'s `target.exs` that is not
  already recorded in its `plugin.exs`. Returns the types actually applied,
  in `target.exs`'s own order.
  """
  @spec run(Path.t(), Path.t()) :: {:ok, [atom()]}
  def run(target, registry_dir) do
    root = Root.new!(target)
    target_exs_path = Root.path(root, "target.exs")

    # If target.exs doesn't exist, return empty list (no plugins to apply)
    if File.regular?(target_exs_path) do
      config = Config.read!(target_exs_path)
      already = already_applied(root)

      newly_listed = Enum.filter(config.plugins, &(&1 not in already))
      Enum.each(newly_listed, &Install.run(&1, target, registry_dir))

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
