defmodule Capstone.VersionGuard do
  @moduledoc """
  Fails loudly when the `Capstone.Config` actually on the code path came from
  an older `capstone` than this project's own dependency tree pins.

  `capstone` ships both as a Mix archive (`mix archive.install hex
  capstone`, giving `mix capstone.new`) and as a project's own dependency
  (giving the engine that keeps that project upgradable). Both can put a
  `:capstone` application on the same VM's code path at once — a developer's
  globally-installed archive, and the project-local build the project's own
  dependency resolves — and only one wins a same-named-module collision.
  Which one wins is decided by Mix's code path ordering, not by intent, so
  the only safe check is: whichever `:capstone` is actually LOADED right
  now, is its version at least what this project's own `mix.lock` pins?

  A newer loaded version than the pin is fine (capstone's guarantees hold
  forward) — only OLDER is the dangerous direction, since it can silently
  reintroduce a fixed bug or omit a schema field the pinned version added.
  """

  alias Mix.Dep.Lock

  @doc """
  Raises `Mix.Error` if the loaded `:capstone` is older than the version
  this project's `mix.lock` pins for it. A no-op — returns `:ok` without
  comparing anything — when either side is unavailable: no `:capstone`
  loaded at all, or no hex-sourced lock entry (a `path:` dependency, as
  during capstone's own pre-publish development, or no dependency on it at
  all — the case for this repository itself, which IS `:capstone` rather
  than depending on it).

  The two lookups are injected as the RAW `Application`/`Mix.Dep.Lock` calls,
  not pre-resolved values, so a test can supply fake raw data and genuinely
  exercise every branch of `loaded_version/1` and `locked_version/1` —
  including the `{:hex, ...}` decode, which no test could reach if the
  injected value were already the resolved string.
  """
  @spec verify!((atom(), atom() -> charlist() | nil), (-> map())) :: :ok
  def verify!(spec_fun \\ &Application.spec/2, lock_fun \\ &Lock.read/0) do
    case {loaded_version(spec_fun), locked_version(lock_fun)} do
      {loaded, locked} when is_binary(loaded) and is_binary(locked) ->
        if Version.compare(loaded, locked) == :lt do
          Mix.raise(
            "capstone #{loaded} is loaded (likely from a globally-installed " <>
              "archive), but this project's mix.lock pins capstone #{locked}. " <>
              "Run `mix archive.install hex capstone` to update the global archive."
          )
        end

        :ok

      _incomparable ->
        :ok
    end
  end

  defp loaded_version(spec_fun) do
    case spec_fun.(:capstone, :vsn) do
      nil -> nil
      vsn -> List.to_string(vsn)
    end
  end

  defp locked_version(lock_fun) do
    case lock_fun.()[:capstone] do
      {:hex, :capstone, version, _hash, _tools, _deps, _repo, _checksum} -> version
      _other -> nil
    end
  end
end
