%{
  deps: ["{:open_api_spex, \"~> 3.22\"}"],
  files: [
    {"lib/APP_web/api_spec.ex", :sole_owner},
    {"lib/APP_web/controllers/health_controller.ex", :sole_owner},
    {"lib/APP_web/schemas.ex", :sole_owner},
    {"lib/APP_web/router.ex", :manual,
     [after: ["    pipe_through :api", "  end", ""], key: :openapi_router]}
  ],
  name: :openapi,
  version: "0.1.0"
}
