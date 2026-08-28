defmodule NewApiApp.CQRS.UniqueCheck do
  @moduledoc """
  Two-layer uniqueness check for a create command's declared unique-field
  groups: a fast Nebulex pre-check, then a race-proof dispatch to
  NewApiApp.CQRS.Reservation at a deterministic stream id. Call reserve/3
  before dispatching the real domain command; on {:error, _} the command
  must not be dispatched. Call release/3 if the domain command's own
  dispatch subsequently fails, to free every group's reservation for a
  retry — event streams are append-only, so "freeing" a ground-truth
  reservation means dispatching Release, not deleting anything; a
  successful create must NEVER call release/3, or the value becomes
  reservable again despite a real entity now holding it.
  """

  alias NewApiApp.CQRS.App
  alias NewApiApp.CQRS.Cache
  alias NewApiApp.CQRS.Reservation.Commands.Release
  alias NewApiApp.CQRS.Reservation.Commands.Reserve

  @ttl :timer.seconds(30)
  @namespace Uniq.UUID.uuid5(:dns, "new_api_app.cqrs.reservation")

  @doc """
  Reserves every field group's key for `schema_tag`/`values`. Returns
  `{:ok, reserved_keys}` if every group was free (both the cache
  pre-check and the Reservation aggregate dispatch succeeded), or
  `{:error, taken_group}` — releasing (cache delete AND a Release
  dispatch) whatever earlier groups this same call had already reserved,
  since the whole multi-group reservation is atomic-or-nothing from the
  caller's point of view.
  """
  @spec reserve(atom(), [[atom()]], map()) :: {:ok, [term()]} | {:error, [atom()]}
  def reserve(schema_tag, unique_fields, values) do
    Enum.reduce_while(unique_fields, {:ok, []}, fn group, {:ok, reserved} ->
      case reserve_group(schema_tag, group, values) do
        {:ok, key} ->
          {:cont, {:ok, [{group, key} | reserved]}}

        :error ->
          Enum.each(reserved, fn {g, key} -> release_group(schema_tag, g, values, key) end)
          {:halt, {:error, group}}
      end
    end)
  end

  @doc """
  Releases every field group's reservation — both the cache key and the
  ground-truth Reservation aggregate (via a Release dispatch). Call this
  only after an aborted create (the real domain command's own dispatch
  failed) — never after a successful one.
  """
  @spec release(atom(), [[atom()]], map()) :: :ok
  def release(schema_tag, unique_fields, values) do
    Enum.each(unique_fields, fn group ->
      release_group(schema_tag, group, values, cache_key(schema_tag, group, values))
    end)
  end

  defp reserve_group(schema_tag, group, values) do
    key = cache_key(schema_tag, group, values)

    case Cache.put_new(key, true, ttl: @ttl) do
      {:ok, false} ->
        :error

      {:ok, true} ->
        reservation_id = reservation_id(schema_tag, group, values)

        case App.dispatch(%Reserve{reservation_id: reservation_id}) do
          :ok ->
            {:ok, key}

          {:error, :already_reserved} ->
            Cache.delete(key, [])
            :error
        end
    end
  end

  defp release_group(schema_tag, group, values, key) do
    reservation_id = reservation_id(schema_tag, group, values)
    :ok = App.dispatch(%Release{reservation_id: reservation_id})
    Cache.delete(key, [])
  end

  defp cache_key(schema_tag, group, values) do
    {schema_tag, group, Enum.map(group, &Map.fetch!(values, &1))}
  end

  defp reservation_id(schema_tag, group, values) do
    name = :erlang.term_to_binary({schema_tag, group, Enum.map(group, &Map.fetch!(values, &1))})
    Uniq.UUID.uuid5(@namespace, name)
  end
end
