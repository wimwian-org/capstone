defmodule NewApiApp.CQRS.Reservation.Commands.Reserve do
  @enforce_keys [:reservation_id]
  defstruct [:reservation_id]
end

defmodule NewApiApp.CQRS.Reservation.Commands.Release do
  @enforce_keys [:reservation_id]
  defstruct [:reservation_id]
end
