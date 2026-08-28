defmodule NewApiApp.CQRS.Reservation.Router do
  use Commanded.Commands.Router

  dispatch(
    [
      NewApiApp.CQRS.Reservation.Commands.Reserve,
      NewApiApp.CQRS.Reservation.Commands.Release
    ],
    to: NewApiApp.CQRS.Reservation,
    identity: :reservation_id
  )
end
