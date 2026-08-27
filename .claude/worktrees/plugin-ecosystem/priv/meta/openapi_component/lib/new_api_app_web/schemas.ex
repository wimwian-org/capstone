defmodule NewApiAppWeb.Schemas do
  @moduledoc "Response schemas the OpenAPI document resolves."

  require OpenApiSpex

  defmodule Health do
    @moduledoc "Liveness response."
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Health",
      description: "Reports that the application is running.",
      type: :object,
      properties: %{status: %OpenApiSpex.Schema{type: :string, example: "ok"}},
      required: [:status]
    })
  end

  defmodule Ready do
    @moduledoc "Readiness response."
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Ready",
      description: "Reports whether the application can serve traffic.",
      type: :object,
      properties: %{
        status: %OpenApiSpex.Schema{type: :string, example: "ok"},
        database: %OpenApiSpex.Schema{type: :string, example: "up"}
      },
      required: [:status, :database]
    })
  end
end
