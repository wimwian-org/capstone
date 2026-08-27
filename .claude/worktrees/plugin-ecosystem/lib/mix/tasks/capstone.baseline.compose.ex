defmodule Mix.Tasks.Capstone.Baseline.Compose do
  # DELIBERATELY no @shortdoc. `lib/**` is in package_files/0, so this task is
  # installed into every project depending on :capstone, where it is
  # meaningless. Without @shortdoc it stays out of `mix help`'s listing while
  # remaining runnable here.
  @moduledoc """
  Builds a DERIVED baseline from a generator baseline plus a plugin.

      mix capstone.baseline.compose web

  `:web` is no longer generated. It is `:api` plus the web layer, so its tree is
  produced rather than downloaded — which is what makes the Svelte layer's
  deletions cease to exist rather than need representing.

  Two steps: RENAME the source tree from its own names to the target's, then
  APPLY the plugin. The rename is `Capstone.Template.capture/2` followed by
  `render/2` — two functions that already exist and are tested — rather than
  new machinery, and it runs before apply because a plugin is captured
  against the source's names and resolves `APP` against the target's.

  Separate from `mix capstone.baseline.record` on purpose. Record is pure over
  directories and shells out to nothing, which is what lets the drift check run
  offline on every commit; this task writes the tree, record hashes it.
  """
  use Mix.Task

  alias Capstone.Baseline
  alias Capstone.Plugin.Apply
  alias Capstone.Template
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
    if File.regular?(@manifest), do: compose(name), else: :ok
  end

  def run(_argv), do: Mix.raise("capstone.baseline.compose expects one entry name")

  defp compose(name) do
    manifest = Baseline.read!(@manifest)
    entry = fetch!(manifest, name)
    # Validated BEFORE either is dereferenced, so a generator baseline asked to
    # compose is told what it lacks rather than raising a KeyError on a key the
    # message never mentions.
    plugin = Path.join("priv/meta", "meta_#{plugin!(entry, name)}")
    source = Map.fetch!(manifest, derived_from!(entry, name))

    File.rm_rf!(entry.path)
    rename!(source, entry)
    {:ok, _applied} = Apply.run(plugin, entry.path)

    Mix.shell().info("composed #{entry.path} from #{source.path} + #{plugin}")
  end

  defp rename!(source, entry) do
    source.path
    |> Baseline.tree()
    |> Map.keys()
    |> Enum.each(&rename_file!(&1, source, entry))
  end

  # `Baseline.tree/1` supplies the paths rather than a fresh wildcard, so the
  # composition prunes exactly what the drift check prunes: no `deps`, no
  # `_build`, no `node_modules`, no build output.
  defp rename_file!(relative, source, entry) do
    contents = File.read!(Path.join(source.path, relative))
    target = Path.join(entry.path, rename_path(relative, source, entry))

    File.mkdir_p!(Path.dirname(target))
    File.write!(target, rename_contents(contents, source, entry))
  end

  # A binary asset takes the VERBATIM path: `Template.capture/2` refuses
  # non-UTF-8 bytes, and a composition that dropped every image and font would
  # produce a baseline nobody could serve.
  defp rename_contents(contents, source, entry) do
    if Template.text?(contents) do
      {:ok, captured} = Template.capture(contents, source.names)
      Template.render(captured, entry.names)
    else
      contents
    end
  end

  defp rename_path(relative, source, entry) do
    relative
    |> Template.placeholder_path(source.names)
    |> Template.resolve_path(entry.names)
  end

  defp fetch!(manifest, name) do
    Enum.find_value(manifest, fn {key, entry} -> if Atom.to_string(key) == name, do: entry end) ||
      Mix.raise("#{name} has no entry in #{@manifest}")
  end

  defp plugin!(%{plugin: plugin}, _name), do: plugin
  defp plugin!(_entry, name), do: Mix.raise("#{name} has no plugin: in #{@manifest}")

  defp derived_from!(%{derived_from: from}, _name), do: from
  defp derived_from!(_entry, name), do: Mix.raise("#{name} has no derived_from: in #{@manifest}")
end
