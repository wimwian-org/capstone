defmodule Capstone.New.Env do
  @moduledoc """
  Environment hygiene for the bootstrap.

  `System.cmd/3` inherits `MIX_*` verbatim. `MIX_EXS` makes the child exit 1
  with "Could not find a Mix.Project"; `MIX_BUILD_PATH` and `MIX_DEPS_PATH`
  silently redirect output; `MIX_ENV=test` makes `deps.compile` a silent no-op
  for an `only: [:dev]` dep — empty output, exit 0, nothing built.

  Scrubbing the child is not enough: the first three also corrupt the PARENT's
  project resolution, so `refuse_poisoned!/1` refuses to start rather than
  half-work. The two lists differ on purpose — `MIX_ENV` is scrubbed from the
  child but is not a refusal, or the archive could not be run from inside any
  `MIX_ENV=test mix ...` invocation.
  """

  @parent_poison ~w(MIX_EXS MIX_BUILD_PATH MIX_DEPS_PATH)
  @scrub ~w(MIX_ENV MIX_EXS MIX_BUILD_PATH MIX_DEPS_PATH MIX_TARGET MIX_BUILD_ROOT)

  @doc "Raises if the caller's environment would silently corrupt the run."
  @spec refuse_poisoned!(%{optional(String.t()) => String.t()}) :: :ok
  def refuse_poisoned!(env) do
    case Enum.filter(@parent_poison, &Map.has_key?(env, &1)) do
      [] -> :ok
      set -> Mix.raise("refusing to run with #{Enum.join(set, ", ")} set; unset them and retry")
    end
  end

  @doc """
  The `env:` option for every child mix invocation.

  `MIX_HOME` and `MIX_ARCHIVES` are deliberately absent: the child needs both to
  find hex, and under mise `MIX_ARCHIVES` wins over `MIX_HOME`.
  """
  @spec child_env() :: [{String.t(), nil}]
  def child_env, do: Enum.map(@scrub, &{&1, nil})
end
