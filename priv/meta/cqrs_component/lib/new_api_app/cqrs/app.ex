defmodule NewApiApp.CQRS.App do
  use Commanded.Application, otp_app: :new_api_app

  router(NewApiApp.CQRS.Reservation.Router)
end
