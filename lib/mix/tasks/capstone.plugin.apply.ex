defmodule Mix.Tasks.Capstone.Plugin.Apply do
  @shortdoc "Applies a derived plugin to a target project"
  @moduledoc """
  Applies a derived plugin to a target project.

      mix capstone.plugin.apply cache ../my_app

  Reads `priv/meta/meta_<name>/`, renders it against the target's OWN name
  triple, and writes each entry according to its ownership mode. Run
  `mix capstone.check` afterwards: an entry whose anchor could not be located
  lands as a conflict region that will not compile until a human resolves it.

  A target holding a `target.exs` also gets a `plugin.exs` recording what
  was written and with which content hashes. One without is installed all the
  same, and the task says so.
  """
  use Mix.Task

  alias Capstone.Plugin.Apply
  alias Capstone.Plugin.Record
  alias Capstone.VersionGuard

  @impl Mix.Task
  def run([name, target]) do
    VersionGuard.verify!()
    dir = Path.join("priv/meta", "meta_#{name}")

    if not File.dir?(dir) do
      Mix.raise("#{dir} does not exist; run mix capstone.plugin.derive #{name}")
    end

    if not File.dir?(target), do: Mix.raise("#{target} does not exist")

    {:ok, plugin} = Apply.run(dir, target)

    Mix.shell().info("applied #{name} to #{target}: #{length(plugin.files)} files")
    report_untracked(target)
    report_manual(plugin, target)
  end

  def run(_argv), do: Mix.raise("capstone.plugin.apply expects a plugin name and a target")

  # The ONLY signal a user gets: recording is silent on an untracked target and
  # nothing later reminds them.
  defp report_untracked(target) do
    if not Record.tracked?(target) do
      Mix.shell().info("  not a Capstone project — no target.exs, so nothing was recorded.")
      Mix.shell().info("  add one to make this project updatable.")
    end
  end

  defp report_manual(plugin, target) do
    keys = for {_path, :manual, opts} <- plugin.files, do: Keyword.fetch!(opts, :key)

    if keys != [] do
      Mix.shell().info(
        "  #{length(keys)} positional entr(ies): #{inspect(keys)} — " <>
          "run `mix capstone.check #{target}` to confirm none needs resolving"
      )
    end
  end
end
