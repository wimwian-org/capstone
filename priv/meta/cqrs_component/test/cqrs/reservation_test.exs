defmodule NewApiApp.CQRS.ReservationTest do
  use ExUnit.Case, async: false

  alias Commanded.EventStore.Adapters.InMemory
  alias NewApiApp.CQRS.App
  alias NewApiApp.CQRS.Reservation.Commands.Release
  alias NewApiApp.CQRS.Reservation.Commands.Reserve

  setup do
    InMemory.reset!(App)
    :ok
  end

  test "reserving a fresh id succeeds" do
    id = Uniq.UUID.uuid4()
    assert :ok = App.dispatch(%Reserve{reservation_id: id})
  end

  test "reserving an already-reserved id fails" do
    id = Uniq.UUID.uuid4()
    assert :ok = App.dispatch(%Reserve{reservation_id: id})
    assert {:error, :already_reserved} = App.dispatch(%Reserve{reservation_id: id})
  end

  test "releasing a reserved id frees it for a fresh reserve" do
    id = Uniq.UUID.uuid4()
    assert :ok = App.dispatch(%Reserve{reservation_id: id})
    assert :ok = App.dispatch(%Release{reservation_id: id})
    assert :ok = App.dispatch(%Reserve{reservation_id: id})
  end

  test "releasing an id that was never reserved fails" do
    id = Uniq.UUID.uuid4()
    assert {:error, :not_reserved} = App.dispatch(%Release{reservation_id: id})
  end
end
