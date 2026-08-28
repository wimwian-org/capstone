defmodule NewApiApp.CQRS.Reservation.Events.Reserved do
  @enforce_keys [:reservation_id]
  defstruct [:reservation_id]
end

defmodule NewApiApp.CQRS.Reservation.Events.Released do
  @enforce_keys [:reservation_id]
  defstruct [:reservation_id]
end
