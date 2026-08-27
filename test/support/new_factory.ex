defmodule Capstone.New.Factory do
  @moduledoc """
  ExMachina factories for `mix capstone.new` and `Capstone.Config`.

  Every factory returns a map or a struct: `ExMachina.merge_attributes/2` calls
  `Map.merge/2` and raises `BadMapError` on a binary, list or function, so a
  scalar datum is always wrapped — `%{argv: [...]}`, never `[...]`.

  Kept as its own module rather than folded into `Capstone.Factory`
  (`test/support/factory.ex`): that one builds fixtures for the
  baseline/manifest domain (`Capstone.Hash`, `Capstone.Manifest`, ...), this
  one builds fixtures for the generator/config domain (`Capstone.New.Options`,
  `Capstone.Config`, ...) — two factories along a real seam in what they
  build, not two packages any more.
  """
  use ExMachina

  alias Capstone.Config
  alias Capstone.Config.Container
  alias Capstone.Config.Container.Sidecars
  alias Capstone.Config.Project
  alias Capstone.Config.Security

  @default_name "my_app"
  @default_github_org "acme"
  @default_mix_exs_variety :stock_otp

  @doc "A fully populated `%Capstone.New.Options{}`."
  @spec options_factory() :: Capstone.New.Options.t()
  def options_factory do
    %Capstone.New.Options{
      name: @default_name,
      app: :my_app,
      module: MyApp,
      base: :otp,
      github_org: @default_github_org,
      capstone: {:hex, "~> 0.1"},
      plugins: []
    }
  end

  @doc "A `%Capstone.Config.Project{}` — random name/org, derived module/app."
  @spec project_factory() :: Project.t()
  def project_factory do
    name = Faker.Internet.domain_word()

    %Project{
      name: name,
      module: Module.concat([Macro.camelize(name)]),
      app: name |> Macro.underscore() |> String.to_atom(),
      github_org: Faker.Internet.domain_word()
    }
  end

  @doc "A `%Capstone.Config.Security{}` with both flags off."
  @spec security_factory() :: Security.t()
  def security_factory, do: %Security{envelope_encryption: false, cloak: false}

  @doc "A `%Capstone.Config.Container.Sidecars{}` with every sidecar off."
  @spec sidecars_factory() :: Sidecars.t()
  def sidecars_factory, do: %Sidecars{valkey: false, openbao: false, nginx: false}

  @doc "A `%Capstone.Config.Container{}` with CI on and every sidecar off."
  @spec container_factory() :: Container.t()
  def container_factory, do: %Container{local_ci: true, sidecars: build(:sidecars)}

  @doc "A fully populated `%Capstone.Config{}` — base :web, no plugins."
  @spec config_factory() :: Config.t()
  def config_factory do
    %Config{
      schema_version: 1,
      base: :web,
      plugins: [],
      project: build(:project),
      security: build(:security),
      container: build(:container)
    }
  end

  @doc "A generated project's `mix.exs`, in the stock shape `mix new` emits."
  @spec mix_exs_source_factory() :: %{variety: atom(), source: String.t()}
  def mix_exs_source_factory, do: mix_exs_source(@default_mix_exs_variety)

  @doc "The same source in a named variety."
  @spec mix_exs_source_factory(map()) :: %{variety: atom(), source: String.t()}
  def mix_exs_source_factory(%{variety: variety}), do: mix_exs_source(variety)

  def mix_exs_source_factory(attrs) when map_size(attrs) == 0,
    do: mix_exs_source(@default_mix_exs_variety)

  @doc "A process environment map, clean unless told otherwise."
  @spec env_map_factory() :: %{env: %{optional(String.t()) => String.t()}}
  def env_map_factory, do: env_map(%{})

  @doc """
  The same map with `:poisoned` names set, and/or explicit `:set` pairs.

  `:poisoned` takes names and gives each a plausible value; `:set` takes the
  pairs verbatim. The two are separate because a test asserting "MIX_ENV is not
  a refusal" must set a variable that is NOT on the poison list.
  """
  @spec env_map_factory(map()) :: %{env: %{optional(String.t()) => String.t()}}
  def env_map_factory(attrs) when is_map(attrs), do: env_map(attrs)

  # The anchor Project.patch_mix_exs/2 splices at is `defp deps do\n    [\n`,
  # so these reproduce `mix new`'s exact indentation. A fixture that merely
  # "looks like" a mix.exs would let the patcher pass here and fail on real
  # generator output.
  defp mix_exs_source(variety) do
    %{variety: variety, source: mix_exs_body(variety)}
  end

  defp mix_exs_body(:stock_otp) do
    """
    defmodule MyApp.MixProject do
      use Mix.Project

      def project do
        [app: :my_app, version: "0.1.0", elixir: "~> 1.20", deps: deps()]
      end

      def application do
        [extra_applications: [:logger]]
      end

      defp deps do
        [
        ]
      end
    end
    """
  end

  defp mix_exs_body(:stock_web) do
    """
    defmodule MyApp.MixProject do
      use Mix.Project

      def project do
        [app: :my_app, version: "0.1.0", elixir: "~> 1.20", deps: deps()]
      end

      def application do
        [mod: {MyApp.Application, []}, extra_applications: [:logger, :runtime_tools]]
      end

      defp deps do
        [
          {:phoenix, "~> 1.8.9"},
          {:jason, "~> 1.2"}
        ]
      end
    end
    """
  end

  defp mix_exs_body(:no_deps_block) do
    """
    defmodule MyApp.MixProject do
      use Mix.Project

      def project do
        [app: :my_app, version: "0.1.0", elixir: "~> 1.20"]
      end
    end
    """
  end

  defp mix_exs_body(:already_patched) do
    """
    defmodule MyApp.MixProject do
      use Mix.Project

      def project do
        [app: :my_app, version: "0.1.0", elixir: "~> 1.20", deps: deps()]
      end

      defp deps do
        [
          {:capstone, "~> 0.1", only: [:dev], runtime: false}
        ]
      end
    end
    """
  end

  defp env_map(attrs) do
    poisoned =
      attrs
      |> Map.get(:poisoned, [])
      |> Map.new(&{&1, "/leaked/#{String.downcase(&1)}"})

    %{env: Map.merge(poisoned, Map.get(attrs, :set, %{}))}
  end
end
