defmodule NewApiAppWeb.ApiSpec do
  @moduledoc "The OpenAPI 3 document served at `/api/v1/openapi`."

  alias OpenApiSpex.Info
  alias OpenApiSpex.OpenApi
  alias OpenApiSpex.Paths
  alias OpenApiSpex.Server

  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      servers: [Server.from_endpoint(NewApiAppWeb.Endpoint)],
      info: %Info{title: "new_api_app", version: "1.0"},
      paths: Paths.from_router(NewApiAppWeb.Router)
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
