defmodule Capstone.New.Shell do
  @moduledoc """
  The two effectful operations of the bootstrap, each behind an injected seam
  so every branch is reachable in-process.

  The seams are not indirection for its own sake: without them the fail-loudly
  branches are reachable only by spawning a subprocess or installing an
  archive, which under `minimum_coverage: 100` forces machine-coupled tests
  into the coverage run — and a flaky coverage gate is how a suite gets tagged
  out and then silently stops running.

  Both defaults are literals in the function head rather than captures or named
  private functions. `&default_runner/2` would leave `defp default_runner/2`
  permanently uncovered, and a closure default costs an uncovered line the
  ignore budget cannot absorb.
  """

  alias Capstone.New.Env

  @type runner :: {module(), atom()}
  @type lookup :: (String.t() -> module() | nil)

  @doc "Runs `mix ARGS` in `cd`, raising with the captured output on any non-zero exit."
  @spec cmd!([String.t()], Path.t(), runner()) :: binary()
  def cmd!(args, cd, {module, function} \\ {System, :cmd}) do
    opts = [cd: cd, env: Env.child_env(), stderr_to_stdout: true]

    case apply(module, function, ["mix", args, opts]) do
      {output, 0} ->
        output

      {output, status} ->
        Mix.raise("mix #{Enum.join(args, " ")} failed with status #{status} in #{cd}:\n#{output}")
    end
  end

  @doc """
  Asserts a generator task is reachable.

  Must be called BEFORE any dependency work: `mix deps.compile` prunes every
  archive off the code path, after which this returns `nil` for an archive that
  is still installed on disk.
  """
  @spec ensure_task_available!(String.t(), lookup()) :: :ok
  def ensure_task_available!(name, lookup \\ &Mix.Task.get/1) do
    if lookup.(name) do
      :ok
    else
      Mix.raise("mix #{name} is not available. Install it with: mix archive.install hex phx_new")
    end
  end
end
