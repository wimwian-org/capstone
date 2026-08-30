defmodule NewApiApp.Valkey.Breaker do
  @moduledoc """
  Circuit breaker + per-call timeout wrapping every call to
  `NewApiApp.Valkey.Cache.L2`, ported from `manage_infra`'s
  `ManageInfra.Cache.Breaker` — see
  docs/superpowers/specs/2026-08-29-valkey-openbao-enhancements-design.md.

  `child_spec/1` delegates straight to `Cache.L2.child_spec/1` — this module
  starts no process of its own; `Cache.L2`'s connection pool is still what's
  supervised, this wraps only the *call*.

  Degrade-safe vs propagate: `get/1`, `put/3`, `delete/1` return a safe
  default (`nil`/`:ok`) when the circuit is open or the call fails — Valkey
  being down degrades the cache to L1-only rather than raising. `put_new/2`,
  `incr/2`, `decr/2` raise instead: those operations can't fake a result that
  stays consistent once L2 comes back.

  Lock-free circuit state: a 3-slot `:atomics` array (state, consecutive
  failure count, opened-at) published once via `:persistent_term`, mutated
  directly by whichever caller observes success/failure — no GenServer
  bottleneck on the hot path.

  Every backend call must name a **bang** function (`get!`, `put!`, `delete!`,
  `put_new!`, `incr!`, `decr!`). `run/2` classifies a call as failed only when
  it *raises*; Nebulex's non-bang counterparts instead *return* `:ok |
  {:error, reason}` (or `{:ok, value}`), which `run/2` would happily wrap as a
  success — silently resetting the failure counter on every L2 error, so the
  circuit could never open.
  """

  @doc false
  defdelegate child_spec(opts), to: NewApiApp.Valkey.Cache.L2

  @state_key {__MODULE__, :state}
  @closed 0
  @open 1

  @doc false
  @spec get(term, keyword) :: term | nil
  def get(key, opts \\ []), do: guarded(:get!, [key, nil, opts], nil)
  @doc false
  @spec put(term, term, keyword) :: :ok
  def put(key, value, opts \\ []), do: guarded(:put!, [key, value, opts], :ok)
  @doc false
  @spec delete(term, keyword) :: :ok
  def delete(key, opts \\ []), do: guarded(:delete!, [key, opts], :ok)

  @doc false
  @spec put_new(term, term, keyword) :: boolean
  def put_new(key, value, opts \\ []), do: bounded(:put_new!, [key, value, opts])
  @doc false
  @spec incr(term, integer, keyword) :: integer
  def incr(key, amount \\ 1, opts \\ []), do: bounded(:incr!, [key, amount, opts])
  @doc false
  @spec decr(term, integer, keyword) :: integer
  def decr(key, amount \\ 1, opts \\ []), do: bounded(:decr!, [key, amount, opts])

  @doc "Force the circuit back to closed with a clean failure count — test/ops utility only."
  @spec reset!() :: :ok
  def reset! do
    ref = state_ref()
    :atomics.put(ref, 1, @closed)
    :atomics.put(ref, 2, 0)
    :atomics.put(ref, 3, 0)
    :ok
  end

  defp guarded(fun, args, default) do
    if circuit_open?() do
      default
    else
      case run(fun, args) do
        {:ok, result} ->
          record_success()
          result

        {:error, _} ->
          record_failure()
          default
      end
    end
  end

  defp bounded(fun, args) do
    if circuit_open?() do
      raise "NewApiApp.Valkey.Breaker: circuit open, refusing L2.#{fun}/#{length(args)}"
    else
      case run(fun, args) do
        {:ok, result} ->
          record_success()
          result

        {:error, :timeout} ->
          record_failure()

          raise "NewApiApp.Valkey.Breaker: L2.#{fun}/#{length(args)} timed out after #{timeout_ms()}ms"

        {:error, {kind, reason, stacktrace}} ->
          record_failure()
          reraise_as(kind, reason, stacktrace)
      end
    end
  end

  defp reraise_as(:error, reason, stacktrace), do: reraise(reason, stacktrace)
  defp reraise_as(:exit, reason, _stacktrace), do: exit(reason)
  defp reraise_as(:throw, reason, _stacktrace), do: throw(reason)

  defp run(fun, args) do
    backend = backend()

    task =
      Task.async(fn ->
        try do
          {:ok, apply(backend, fun, args)}
        rescue
          e -> {:error, {:error, e, __STACKTRACE__}}
        catch
          kind, reason -> {:error, {kind, reason, __STACKTRACE__}}
        end
      end)

    case Task.yield(task, timeout_ms()) do
      {:ok, result} ->
        result

      nil ->
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end
  end

  defp circuit_open? do
    ref = state_ref()

    case :atomics.get(ref, 1) do
      @closed ->
        false

      @open ->
        opened_at = :atomics.get(ref, 3)
        System.monotonic_time(:millisecond) - opened_at < cooldown_ms()
    end
  end

  defp record_success do
    ref = state_ref()
    :atomics.put(ref, 2, 0)
    :atomics.put(ref, 1, @closed)
  end

  defp record_failure do
    ref = state_ref()
    failures = :atomics.add_get(ref, 2, 1)

    if failures >= failure_threshold() do
      :atomics.put(ref, 1, @open)
      :atomics.put(ref, 3, System.monotonic_time(:millisecond))
    end
  end

  defp state_ref do
    case :persistent_term.get(@state_key, nil) do
      nil ->
        ref = :atomics.new(3, signed: true)
        :persistent_term.put(@state_key, ref)
        ref

      ref ->
        ref
    end
  end

  defp backend, do: config()[:backend] || NewApiApp.Valkey.Cache.L2
  defp timeout_ms, do: config()[:timeout_ms]
  defp failure_threshold, do: config()[:failure_threshold]
  defp cooldown_ms, do: config()[:cooldown_ms]
  defp config, do: Application.get_env(:new_api_app, __MODULE__, [])
end
