defmodule Capstone.New.Bootstrap do
  @moduledoc """
  The `mix capstone.new` sequence, with every effect injected.

  It lives here rather than in `Mix.Tasks.Capstone.New.run/1` for a coverage
  reason that is structural, not stylistic: `@impl Mix.Task` fixes `run/1`'s
  arity at 1, so there is no parameter through which a fake runner could reach
  the sequence. Measured with the sequence inlined in `run/1`, 12 of 14 relevant
  lines were reachable only from a `@tag :toolchain` test that
  `ExUnit.start(exclude:)` removes from the coverage run, and rescuing them with
  `coveralls-ignore` blew the 5% budget several times over.

  ## The call order is load-bearing

  The generator probe must precede any dependency work, because
  `mix deps.compile` prunes every archive off the code path
  (`Code.delete_paths(current_paths -- loaded_paths)`). Measured: archive paths
  go from three entries to `[]` across that one call, after which
  `Mix.Task.get("phx.new")` returns `nil` even though phx_new is installed on
  disk.

  Patching and config-writing precede dependency work too, so a project whose
  `mix.exs` cannot be patched is never compiled against a dep it does not
  declare.

  Plugin application sits between the `target.exs` write and dependency work,
  for two independent reasons: it must follow the write, because
  `Capstone.Plugin.Install` reads `target.exs` back through
  `Capstone.Config`; and it must precede `deps.get`/`deps.compile`, because a
  plugin's `deps:` are written into `mix.exs` there and would otherwise never
  be fetched.

  Each plugin is synced (`effects.sync`, `Capstone.Plugin.Remote.sync!/2` by
  default) immediately before it is installed, never once for the whole
  batch up front — a later plugin's sync failure must not undo an earlier
  plugin's already-completed install.
  """

  alias Capstone.New.Env
  alias Capstone.New.Options
  alias Capstone.New.Project
  alias Capstone.New.Shell
  alias Capstone.Plugin.Install
  alias Capstone.Plugin.Registry
  alias Capstone.Plugin.Remote

  @typedoc "Every side effect `run/3` performs, injected so each is fake-able in-process."
  @type effects :: %{
          getenv: (-> %{optional(String.t()) => String.t()}),
          lookup: Shell.lookup(),
          generator: (String.t(), [String.t()] -> any()),
          runner: Shell.runner(),
          shell: module(),
          sync: (atom(), Path.t() -> :ok)
        }

  @doc "The real effects."
  @spec defaults() :: effects()
  def defaults do
    %{
      getenv: &System.get_env/0,
      lookup: &Mix.Task.get/1,
      generator: &Mix.Task.run/2,
      runner: {System, :cmd},
      shell: Mix.shell(),
      sync: &Remote.sync!/2
    }
  end

  @doc "Runs the bootstrap. See this module's documentation for the ordering rules."
  @spec run(Options.t(), effects(), Path.t()) :: :ok
  def run(%Options{} = opts, effects, registry_dir \\ Registry.default_dir()) do
    Env.refuse_poisoned!(effects.getenv.())

    generator = Options.generator(opts)
    Shell.ensure_task_available!(generator, effects.lookup)
    effects.generator.(generator, Options.generator_argv(opts))

    patch_mix_exs!(opts)
    File.write!(Path.join(opts.name, "target.exs"), Project.render_config(opts))
    apply_plugins!(opts, registry_dir, effects.sync)

    Shell.cmd!(["deps.get"], opts.name, effects.runner)
    Shell.cmd!(["deps.compile"], opts.name, effects.runner)

    effects.shell.info("Generated #{opts.name}. Next: cd #{opts.name} && mix test")

    :ok
  end

  defp apply_plugins!(opts, registry_dir, sync) do
    Enum.each(opts.plugins, fn type ->
      sync.(type, registry_dir)
      Install.run(type, opts.name, registry_dir)
    end)
  end

  defp patch_mix_exs!(opts) do
    path = Path.join(opts.name, "mix.exs")

    case Project.patch_mix_exs(File.read!(path), Options.dep_line(opts)) do
      {:ok, patched} -> File.write!(path, patched)
      {:error, reason} -> Mix.raise("could not patch #{path}: #{reason}")
    end
  end
end
