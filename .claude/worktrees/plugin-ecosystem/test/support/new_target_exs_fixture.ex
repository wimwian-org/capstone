defmodule Capstone.New.TargetExsFixture do
  @moduledoc false

  alias Capstone.Config

  @spec render(Config.t()) :: String.t()
  def render(%Config{} = config) do
    """
    %{
      schema_version: #{inspect(config.schema_version)},
      base: #{inspect(config.base)},
      plugins: #{inspect(config.plugins)},
      project: [
        name: #{inspect(config.project.name)},
        module: #{inspect(config.project.module)},
        app: #{inspect(config.project.app)},
        github_org: #{inspect(config.project.github_org)}
      ],
      security: [
        envelope_encryption: #{inspect(config.security.envelope_encryption)},
        cloak: #{inspect(config.security.cloak)}
      ],
      container: [
        local_ci: #{inspect(config.container.local_ci)},
        sidecars: [
          valkey: #{inspect(config.container.sidecars.valkey)},
          openbao: #{inspect(config.container.sidecars.openbao)},
          nginx: #{inspect(config.container.sidecars.nginx)}
        ]
      ]
    }
    """
  end
end
