defmodule NewApiAppWeb.Router do
  use NewApiAppWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", NewApiAppWeb do
    pipe_through :api
  end

  pipeline :openapi do
    plug OpenApiSpex.Plug.PutApiSpec, module: NewApiAppWeb.ApiSpec
  end

  pipeline :openapi_ui do
    plug :accepts, ["html"]
  end

  scope "/api/v1", NewApiAppWeb do
    pipe_through [:api, :openapi]

    get "/health", HealthController, :health
    get "/ready", HealthController, :ready
  end

  scope "/api/v1" do
    pipe_through :openapi

    get "/openapi", OpenApiSpex.Plug.RenderSpec, []
  end

  scope "/api/v1/docs" do
    pipe_through :openapi_ui

    get "/", OpenApiSpex.Plug.SwaggerUI, path: "/api/v1/openapi"
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:new_api_app, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: NewApiAppWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
