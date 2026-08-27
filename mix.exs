defmodule Capstone.MixProject do
  use Mix.Project

  # `@external_resource` is what makes a version bump recompile this file. The
  # attribute is read at COMPILE time, so without it `mix.exs` keeps whatever
  # number it was compiled with and a release can publish a version the file no
  # longer holds.
  @version_file Path.join(__DIR__, ".version")
  @external_resource @version_file
  @version @version_file |> File.read!() |> String.trim()

  @github "https://github.com/wimwian-org/capstone"

  def project do
    [
      app: :capstone,
      version: @version,
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :test,
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      test_ignore_filters: [&String.starts_with?(&1, "test/support/")],
      dialyzer: dialyzer(),
      name: "Capstone",
      description: description(),
      package: package(),
      source_url: @github,
      cli: cli(),
      docs: docs()
    ]
  end

  # `:preferred_cli_env` is deprecated on 1.15+.
  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application, do: [extra_applications: [:logger]]

  # Vendored source lives under `lib/`, which hex ships by default. The custom
  # Credo checks are deliberately NOT here: they live at the repository root,
  # outside every `elixirc_paths`, so they never reach a compiled application --
  # `CredoCommentTagsTest` asserts exactly that. `.credo.exs` loads them through
  # a root-relative `requires:` glob, and the one test that calls a check
  # directly requires its source from `test_helper.exs`.
  defp elixirc_paths(:test), do: ["lib", "test/support"]

  defp elixirc_paths(_env), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  #
  # Every entry MUST carry an `only:` that excludes `:prod` -- see
  # `CredoNoRuntimeDepsTest`/`Capstone.Credo.Check.Design.NoRuntimeDeps`.
  # Capstone is meant to be installed as a `mix archive` (see README), and an
  # archive never bundles its dependencies, so a `:prod`-visible requirement
  # here would constrain -- or outright break -- every project that installs
  # it. That is also why third-party libraries the engine actually needs at
  # runtime (Sourceror, TypedStruct, Vex, simple_enum) are vendored under
  # `lib/capstone/vendor/` instead of declared here.
  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.23", only: :dev, runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:ex_machina, "~> 2.8", only: :test},
      {:excoveralls, "~> 0.18", only: :test},
      {:faker, "~> 0.19", only: :test},
      {:devops, "~> 0.1", only: :dev},
      {:git_ops, "~> 2.1", only: :dev},
      {:sobelow, "~> 0.15", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "The Capstone engine and its `mix capstone.new` project generator: " <>
      "scaffolds Elixir/Phoenix projects with a Svelte 5 UI layer and keeps " <>
      "them upgradable across regenerations."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @github},
      files: ~w(
        lib
        priv/plugins
        mix.exs
        .formatter.exs
        .version
        README.md
        LICENSE
      )
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:eex, :mix, :ex_unit],
      flags: [:error_handling, :extra_return, :missing_return, :unknown],
      ignore_warnings: ".dialyzer_ignore.exs",
      list_unused_filters: true
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "goals.md"]
    ]
  end
end
