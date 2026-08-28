defmodule NewApiApp.CQRS.Reservation do
  @moduledoc """
  A minimal aggregate whose entire purpose is uniqueness ground truth.
  Its identity IS the reservation: a deterministic stream id derived from
  a schema tag, a field group, and that group's values
  (see NewApiApp.CQRS.UniqueCheck.reservation_id/3). Dispatching Reserve
  to an id that already has an active Reserved applied fails — this is
  race-proof because the event store serializes appends per stream.

  Event streams are append-only — a reservation can never be deleted, so
  a failed/aborted create (a later unique-field group taken, or the real
  domain command's own dispatch failing afterward) must explicitly
  dispatch Release to free the id for reuse; a successful create simply
  never releases it, leaving the reservation permanent (correct — the
  value is now genuinely, permanently taken by the real entity).
  """

  defstruct [:id, released: true]

  alias NewApiApp.CQRS.Reservation.Commands.Release
  alias NewApiApp.CQRS.Reservation.Commands.Reserve
  alias NewApiApp.CQRS.Reservation.Events.Released
  alias NewApiApp.CQRS.Reservation.Events.Reserved

  def execute(%__MODULE__{released: true}, %Reserve{reservation_id: id}) do
    %Reserved{reservation_id: id}
  end

  def execute(%__MODULE__{released: false}, %Reserve{}) do
    {:error, :already_reserved}
  end

  def execute(%__MODULE__{released: false}, %Release{reservation_id: id}) do
    %Released{reservation_id: id}
  end

  def execute(%__MODULE__{released: true}, %Release{}) do
    {:error, :not_reserved}
  end

  def apply(%__MODULE__{} = state, %Reserved{reservation_id: id}) do
    %__MODULE__{state | id: id, released: false}
  end

  def apply(%__MODULE__{} = state, %Released{}) do
    %__MODULE__{state | released: true}
  end
end
