defmodule NewApiApp.CQRS.Reservation.Events.Reserved do
  @derive Jason.Encoder
  @enforce_keys [:reservation_id]
  defstruct [:reservation_id]
end

defmodule NewApiApp.CQRS.Reservation.Events.Released do
  @derive Jason.Encoder
  @enforce_keys [:reservation_id]
  defstruct [:reservation_id]
end
