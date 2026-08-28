defmodule NewApiApp.CQRS.Dispatcher do
  @moduledoc """
  Single entry point for CQRS commands and queries. dispatch/2 does NOT
  return the created struct (event sourcing decouples persisting an
  event from projecting a read model) — it returns :ok | {:error,
  reason}, matching Commanded.Application.dispatch/2's own contract.
  Fetch the resulting read-model row separately via query/2, after
  dispatch/2 returns :ok.
  """

  alias NewApiApp.CQRS.App
  alias NewApiApp.CQRS.UniqueCheck

  @doc """
  `command_module` must implement `NewApiApp.CQRS.Command`. Reserves
  every unique-field group (see UniqueCheck) before forwarding to
  NewApiApp.CQRS.App.dispatch/2 with consistency: :strong, so a caller
  that immediately calls query/2 after :ok sees the projected row.
  """
  @spec dispatch(module(), map()) :: :ok | {:error, term()}
  def dispatch(command_module, params) do
    command = command_module.build(params)
    # Unique-field values come from the BUILT command struct, not the
    # raw `params` input — build/1 may normalize (cast types, trim,
    # downcase an email, etc.), and the reservation must match what
    # actually gets dispatched, or a normalization difference could let
    # a duplicate through.
    values = Map.from_struct(command)

    case UniqueCheck.reserve(command_module.schema_tag(), command_module.unique_fields(), values) do
      {:ok, _reserved} ->
        case App.dispatch(command, consistency: :strong) do
          :ok ->
            :ok

          {:error, reason} ->
            UniqueCheck.release(
              command_module.schema_tag(),
              command_module.unique_fields(),
              values
            )

            {:error, reason}
        end

      {:error, taken_group} ->
        {:error, {:already_taken, taken_group}}
    end
  end

  @spec query(module(), map()) :: {:ok, term()} | {:error, term()}
  def query(query_module, params), do: query_module.run(params)
end
