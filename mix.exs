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
  def application, do: [extra_applications: [:logger, :inets, :ssl]]

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
    ] ++ vendored_upstream_docs_deps()
  end

  # The real, un-renamespaced upstream packages `lib/capstone/vendor/` pins
  # copies of, pinned to the exact version each copy was vendored at
  # (`hex_metadata.config` in each vendor directory). `only: :dev,
  # runtime: false, compile: false` -- never compiled, so nothing here
  # collides with (or substitutes for) the vendored `Capstone.Vendor.*`
  # copies actually used at runtime; present solely so `mix docs` can
  # resolve/link doc references to the real package a vendored type
  # corresponds to, e.g. `Capstone.Source.MixExs.append_element/4`'s
  # `@spec`, instead of linking into `Capstone.Vendor.*`, which
  # `filter_modules` in `docs/0` deliberately excludes from published docs.
  defp vendored_upstream_docs_deps do
    [
      {:sourceror, "== 1.12.2", only: :dev, runtime: false},
      {:vex, "== 0.9.2", only: :dev, runtime: false},
      {:simple_enum, "== 1.0.0", only: :dev, runtime: false},
      {:typedstruct, "== 0.5.4", only: :dev, runtime: false}
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

  # Every ex_doc warning traced to one of two causes, both addressed below
  # rather than by editing vendored source: `lib/capstone/vendor/` is a
  # pinned copy of four upstream trees (see goals.md's "Vendoring is
  # ownership" -- bugs included, no fixes applied while they stay pinned),
  # so its own doc comments referencing ITS OWN hidden callbacks/missing
  # guide files are excluded from doc generation entirely via
  # `filter_modules`, rather than patched one warning at a time. Prose
  # elsewhere that mentions a vendored module by name (moduledocs
  # explaining the mechanism, not `@spec`s) names it without linking, via
  # `skip_code_autolink_to` -- `vendored_upstream_docs_deps/0` below exists
  # for the one place that DOES want a real, working hexdocs link instead
  # (`Capstone.Source.MixExs.append_element/4`'s `@spec`; see the comment
  # there). `Mix.Dep.Lock` and `Mix.Tasks.Capstone.New.run/1` are the two
  # remaining entries from capstone's own code -- real, intentional
  # references to genuinely hidden/undocumented modules, named but never
  # auto-linked.
  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "docs/guides/building-a-plugin.md",
        "docs/guides/applying-a-plugin.md",
        "docs/guides/upgrading-the-installation.md",
        "goals.md",
        "LICENSE"
      ],
      filter_modules: fn module, _metadata ->
        not (module |> to_string() |> String.contains?(".Vendor."))
      end,
      skip_code_autolink_to: [
        "Mix.Dep.Lock",
        "Mix.Tasks.Capstone.New.run/1",
        "Capstone.Manifest.validate_timestamp!/2",
        "Capstone.Config.Literal.path/0",
        "Capstone.Vendor.Sourceror"
      ]
    ]
  end
end
