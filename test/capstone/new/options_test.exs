defmodule Capstone.New.OptionsTest do
  use ExUnit.Case, async: true

  alias Capstone.New.Factory
  alias Capstone.New.Options
  alias Capstone.New.TargetExsFixture

  defp write_target_exs!(config) do
    path = Path.join(System.tmp_dir!(), "target-#{System.unique_integer([:positive])}.exs")
    File.write!(path, TargetExsFixture.render(config))
    on_exit(fn -> File.rm!(path) end)
    path
  end

  describe "parse!/1 — happy path, one per base" do
    for base <- [:api, :web, :both] do
      test "base #{base}: --path derives every field from target.exs" do
        config = %{Factory.build(:config) | base: unquote(base)}
        path = write_target_exs!(config)

        opts = Options.parse!(["--path", path])

        assert opts.base == unquote(base)
        assert opts.name == config.project.name
        assert opts.app == config.project.app
        assert opts.module == config.project.module
        assert opts.github_org == config.project.github_org
        assert opts.capstone == {:hex, "~> 0.1"}
      end
    end
  end

  test "parse!/1 requires --path" do
    assert_raise Options.Error, ~r/--path is required/, fn -> Options.parse!([]) end
  end

  test "parse!/1 rejects an unknown switch" do
    path = write_target_exs!(Factory.build(:config))

    assert_raise Options.Error, ~r/unknown switch/, fn ->
      Options.parse!(["--path", path, "--base", "api"])
    end
  end

  test "parse!/1 rejects any positional argument" do
    path = write_target_exs!(Factory.build(:config))

    assert_raise Options.Error, ~r/no positional arguments/, fn ->
      Options.parse!(["--path", path, "extra"])
    end
  end

  test "parse!/1 surfaces Capstone.Config.Error for an invalid target.exs" do
    path = write_target_exs!(Factory.build(:config))
    File.write!(path, "%{}")

    assert_raise Capstone.Config.Error, ~r/missing_key/, fn ->
      Options.parse!(["--path", path])
    end
  end

  test "from_config!/1 maps a %Capstone.Config{} directly" do
    config = %{Factory.build(:config) | base: :api}

    opts = Options.from_config!(config)

    assert opts == %Options{
             name: config.project.name,
             app: config.project.app,
             module: config.project.module,
             base: config.base,
             github_org: config.project.github_org,
             capstone: {:hex, "~> 0.1"},
             plugins: config.plugins
           }
  end

  test "from_config!/1 carries the config's plugins list through" do
    config = Factory.build(:config, base: :api, plugins: [:cache])

    assert Options.from_config!(config).plugins == [:cache]
  end

  describe "from_config!/1 — plugins stays declared-only, never implied" do
    test "base: :web with no explicit plugins stays empty" do
      config = Factory.build(:config, base: :web, plugins: [])

      assert Options.from_config!(config).plugins == []
    end

    test "base: :both with no explicit plugins stays empty" do
      config = Factory.build(:config, base: :both, plugins: [])

      assert Options.from_config!(config).plugins == []
    end
  end

  describe "implied_plugins/1" do
    test "returns [] for :api" do
      assert Options.implied_plugins(:api) == []
    end

    test "returns [:web_layer] for :web and :both" do
      assert Options.implied_plugins(:web) == [:web_layer]
      assert Options.implied_plugins(:both) == [:web_layer]
    end
  end

  describe "effective_plugins/1" do
    test "base: :web prepends :web_layer" do
      opts = Factory.build(:options, base: :web, plugins: [])

      assert Options.effective_plugins(opts) == [:web_layer]
    end

    test "base: :both prepends :web_layer" do
      opts = Factory.build(:options, base: :both, plugins: [])

      assert Options.effective_plugins(opts) == [:web_layer]
    end

    test "base: :api implies nothing" do
      opts = Factory.build(:options, base: :api, plugins: [:cache])

      assert Options.effective_plugins(opts) == [:cache]
    end

    test "an explicit :web_layer entry does not duplicate the implied one" do
      opts = Factory.build(:options, base: :web, plugins: [:web_layer, :cache])

      assert Options.effective_plugins(opts) == [:web_layer, :cache]
    end

    test "implied plugins come before explicit ones" do
      opts = Factory.build(:options, base: :web, plugins: [:cache])

      assert Options.effective_plugins(opts) == [:web_layer, :cache]
    end
  end

  test "generator/1 and generator_argv/1 differ by base, :both included" do
    otp = Factory.build(:options, base: :otp, name: "a", app: :a, module: A)
    web = Factory.build(:options, base: :web, name: "b", app: :b, module: B)
    both = Factory.build(:options, base: :both, name: "c", app: :c, module: C)

    assert Options.generator(otp) == "new"
    assert Options.generator(web) == "phx.new"
    assert Options.generator(both) == "phx.new"

    # --no-install is REQUIRED: without it phx.new PROMPTS "Fetch and install
    # dependencies? [Yn]" and blocks on a TTY. It changes zero file content.
    assert "--no-install" in Options.generator_argv(web)
    assert "--no-install" in Options.generator_argv(both)
    assert "--no-version-check" in Options.generator_argv(web)
    refute "--no-install" in Options.generator_argv(otp)
  end

  test "generator_argv/1 leads with NAME and carries the module and app" do
    opts = Factory.build(:options, base: :otp, name: "my_app", app: :my_app, module: MyApp)

    assert [name | rest] = Options.generator_argv(opts)
    assert name == "my_app"
    assert "MyApp" in rest
    assert "my_app" in rest
  end

  test "dep_line/1 emits a path dep or a hex dep, both dev-only and non-runtime" do
    path = Factory.build(:options, capstone: {:path, "/repo"})
    hex = Factory.build(:options, capstone: {:hex, "~> 0.1"})

    assert Options.dep_line(path) ==
             ~s|{:capstone, path: "/repo", only: [:dev], runtime: false}|

    assert Options.dep_line(hex) ==
             ~s|{:capstone, "~> 0.1", only: [:dev], runtime: false}|
  end

  test "dep_line/1 output parses as a single dep tuple" do
    # A dep line that does not parse fails much later, inside the generated
    # project's deps.get, with a message that names this project nowhere.
    for opts <- [
          Factory.build(:options, capstone: {:path, "/repo"}),
          Factory.build(:options, capstone: {:hex, "~> 0.1"})
        ] do
      assert dep_name(wrapped_dep_ast(opts)) == :capstone
    end
  end

  defp wrapped_dep_ast(opts) do
    # Wrapped in a list so the parse also proves the line is exactly ONE element:
    # a stray comma would arrive here as two.
    [ast] =
      opts
      |> Options.dep_line()
      |> then(&"[#{&1}]")
      |> Code.string_to_quoted!(emit_warnings: false)

    ast
  end

  # The two dep forms quote differently and both are valid Mix deps: the path
  # form `{:capstone, path: ..., only: ...}` is a 2-tuple and quotes to a literal,
  # while the hex form `{:capstone, "~> 0.1", only: ...}` is a 3-tuple and quotes
  # to {:{}, meta, elements}. Matching only the latter would silently stop
  # checking the path form, which is the one both toolchain tests actually use.
  defp dep_name({:{}, _meta, [name | _rest]}), do: name
  defp dep_name({name, _opts}), do: name
end
