defmodule Capstone.New.Integration.TargetProjectTest do
  @moduledoc """
  The whole `mix capstone.new` journey against the REAL generator.

  `Capstone.New.BootstrapTest` covers the same sequence with the generator faked, so
  what is new here is only that the fake is gone: `Mix.Task.run/2` really runs
  `mix new`, and the patcher and the config writer are held against the bytes a
  stock generator emits rather than against a fixture written to resemble them.
  That distinction is the one this file exists for — a `mix.exs` fixture that
  merely looks right lets `Capstone.New.Project.patch_mix_exs/2` pass here and fail on
  a real project.

  ## Two ways in, on purpose

  `--path` is the only way `mix capstone.new` itself accepts input now, and
  `target.exs`'s schema (`Capstone.Config`) has no `:otp` value and no
  dependency-source field — so a bare OTP base and a `{:path, ...}` `capstone`
  dependency are unreachable through it. Both stay
  covered here by building a `%Capstone.New.Options{}` directly and handing it
  to `Bootstrap.run/2`, which has never cared how its `Options` argument was
  built. The `:otp` base is also simply the fastest way to exercise the
  patcher/config-writer/deps-ordering mechanics without a network call, which
  is why most of this file's tests use it rather than because `:otp` itself
  needs proving.

  ## The one effect still injected

  `deps.get` and `deps.compile` are recorded rather than run. They are the two
  steps that need the network and a resolvable `:capstone`, and running them would
  make this suite fail on a plane rather than on a defect. Their ORDER and their
  `cd:` are asserted, and `Capstone.New.Bootstrap`'s moduledoc explains why that order
  is load-bearing; everything else in `Capstone.New.Bootstrap.defaults/0` is real.

  ## Why the config assertion stops where it does

  This archive ships zero runtime dependencies of its own, and it compiles
  `Capstone.Config` as part of itself — the file is still read back here with
  `Code.eval_string/1` for the fast tests, checking shape and nothing else,
  because that is what a hand-authored `target.exs` fixture can promise. The
  `--path` block below goes one step further and reads the written file back
  through `Capstone.Config.read!/1` itself, so at least one test in this suite
  pins the stronger claim here rather than leaving it to `Capstone.Config`'s
  own test suite alone.
  """

  # async: false — every test moves the node-global cwd and re-enables a task in
  # the shared Mix task registry.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Capstone.New.Bootstrap
  alias Capstone.New.Factory
  alias Capstone.New.Options
  alias Capstone.New.TargetExsFixture
  alias Capstone.Plugin.Package

  defmodule RecordingRunner do
    @moduledoc false
    def cmd(_bin, args, opts) do
      send(self(), {:cmd, args, opts})

      {"", 0}
    end
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "target-project-#{System.unique_integer([:positive])}")
    original = File.cwd!()

    File.mkdir_p!(dir)

    on_exit(fn ->
      File.cd!(original)
      File.rm_rf!(dir)
    end)

    {:ok, dir: dir}
  end

  # `Mix.Task.run/2` runs a task at most once per node, and the bootstrap calls
  # it through the injected `:generator`. Without this a second test in the same
  # run gets `:noop` back and generates nothing, which reads as the patcher
  # having failed.
  #
  # The generator effect calls the task module directly rather than going
  # through `Mix.Task.run/2`, purely to sidestep that run-once bookkeeping --
  # every test here needs a real `mix new`/`mix phx.new` run, not the second
  # test getting `:noop` because the first already ran the task once for this
  # node. The generator is still the real one -- same module, same `run/1` --
  # with only Mix's run-once tracking removed. Production is unaffected:
  # `mix capstone.new` is a top-level invocation that runs the task exactly
  # once, so `Mix.Task.run/2`'s bookkeeping never gets in the way there.
  defp generate!(dir, %Options{} = opts) do
    Mix.Task.reenable("new")
    Mix.Task.reenable("phx.new")

    generator = fn task, task_argv ->
      module = Mix.Task.get!(task)
      module.run(task_argv)
    end

    effects = %{
      Bootstrap.defaults()
      | runner: {RecordingRunner, :cmd},
        generator: generator
    }

    capture_io(fn -> File.cd!(dir, fn -> assert Bootstrap.run(opts, effects) == :ok end) end)

    Path.join(dir, opts.name)
  end

  # The `--path` entry point: renders a real target.exs, parses it exactly as
  # `mix capstone.new` would, then generates from the result.
  defp generate!(dir, %Capstone.Config{} = config) do
    path = Path.join(dir, "target-#{System.unique_integer([:positive])}.exs")
    File.write!(path, TargetExsFixture.render(config))

    generate!(dir, Options.parse!(["--path", path]))
  end

  # Same as generate!/2, plus a plugin registry_dir threaded through to
  # Bootstrap.run/3 — for the plugin-application test below.
  defp generate!(dir, %Options{} = opts, registry_dir) do
    Mix.Task.reenable("new")
    Mix.Task.reenable("phx.new")

    generator = fn task, task_argv ->
      module = Mix.Task.get!(task)
      module.run(task_argv)
    end

    effects = %{
      Bootstrap.defaults()
      | runner: {RecordingRunner, :cmd},
        generator: generator
    }

    capture_io(fn ->
      File.cd!(dir, fn -> assert Bootstrap.run(opts, effects, registry_dir) == :ok end)
    end)

    Path.join(dir, opts.name)
  end

  defp eval_config!(project) do
    {config, _bindings} = project |> Path.join("target.exs") |> File.read!() |> Code.eval_string()

    config
  end

  describe "generating from a direct Options build (base :otp, fast path)" do
    test "lays down a stock mix new tree", %{dir: dir} do
      opts = Factory.build(:options, base: :otp, name: "my_app", app: :my_app, module: MyApp)
      project = generate!(dir, opts)

      for file <- ~w(mix.exs README.md .formatter.exs .gitignore lib/my_app.ex
                     test/my_app_test.exs test/test_helper.exs) do
        assert File.regular?(Path.join(project, file)), "#{file} is missing"
      end
    end

    test "patches the generated mix.exs so it still parses and declares :capstone", %{dir: dir} do
      opts = Factory.build(:options, base: :otp, name: "my_app", app: :my_app, module: MyApp)
      project = generate!(dir, opts)
      source = File.read!(Path.join(project, "mix.exs"))

      # Parsed, not merely matched. The patcher is a string splice into a real
      # generator's output, and a splice that lands one line off produces a
      # mix.exs that greps clean and will not compile.
      assert {:ok, _ast} = Code.string_to_quoted(source)
      assert source =~ ~s|{:capstone, "~> 0.1", only: [:dev], runtime: false}|
    end

    test "honours a {:path, ...} capstone dependency source", %{dir: dir} do
      # There is no CLI flag for this any more (target.exs has no
      # dependency-source field) — {:path, ...} stays reachable by building
      # Options directly, which is exactly what this test does.
      checkout = Path.join(dir, "scaffolder_checkout")

      opts =
        Factory.build(:options,
          base: :otp,
          name: "my_app",
          app: :my_app,
          module: MyApp,
          capstone: {:path, checkout}
        )

      project = generate!(dir, opts)
      source = File.read!(Path.join(project, "mix.exs"))

      assert {:ok, _ast} = Code.string_to_quoted(source)
      assert source =~ ~s|{:capstone, path: "#{checkout}", only: [:dev], runtime: false}|
      refute source =~ ~s|{:capstone, "~> 0.1"|
    end

    test "writes a target.exs naming the base and the project", %{dir: dir} do
      opts = Factory.build(:options, base: :otp, name: "my_app", app: :my_app, module: MyApp)
      project = generate!(dir, opts)

      assert eval_config!(project) == %{
               schema_version: 1,
               base: :otp,
               project: [name: "my_app", module: MyApp, app: :my_app, github_org: opts.github_org],
               plugins: []
             }
    end

    test "carries a custom app and module through to the real generator and the config",
         %{dir: dir} do
      opts = Factory.build(:options, base: :otp, name: "my_app", app: :other_app, module: Other)
      project = generate!(dir, opts)

      # `mix new` names the root source file after the MODULE and the OTP
      # application after `--app`, neither of them after the directory. Both
      # land, which is what proves `Options.generator_argv/1` reached the
      # generator rather than merely being well-formed.
      assert File.read!(Path.join(project, "lib/other.ex")) =~ "defmodule Other do"
      assert File.read!(Path.join(project, "mix.exs")) =~ "app: :other_app"
      refute File.exists?(Path.join(project, "lib/my_app.ex"))

      config = eval_config!(project)
      assert config.project[:app] == :other_app
      assert config.project[:module] == Other
      assert config.project[:name] == "my_app"
    end

    test "runs deps.get then deps.compile, both inside the generated project", %{dir: dir} do
      opts = Factory.build(:options, base: :otp, name: "my_app", app: :my_app, module: MyApp)
      generate!(dir, opts)

      # assert_received is ordered, so this pins the sequence and not just the
      # membership. Anything before the generator would be dependency work
      # against a project that does not exist yet.
      assert_received {:cmd, ["deps.get"], get_opts}
      assert_received {:cmd, ["deps.compile"], compile_opts}
      assert get_opts[:cd] == "my_app"
      assert compile_opts[:cd] == "my_app"

      # MIX_* is scrubbed from the child or an outer `MIX_ENV=test` turns
      # deps.compile into a silent no-op for an `only: [:dev]` dependency.
      assert {"MIX_ENV", nil} in get_opts[:env]
    end
  end

  describe "generating via --path against the real target.exs reader" do
    @tag :toolchain
    test "drives phx.new with the flags that keep HTML and assets out, for :api and :both",
         %{dir: dir} do
      # Compiling this project's own dependencies pruned every archive off the
      # code path before the suite started — the exact effect
      # `Capstone.New.Bootstrap`'s moduledoc records as the reason the generator
      # probe must precede dependency work. Restoring them is what lets a real
      # `phx.new` run in-process at all; without it `Mix.Task.get/1` returns nil
      # for an archive that is installed on disk.
      Mix.Local.append_archives()

      for base <- [:api, :both] do
        name = "app_#{base}"
        config = Factory.build(:config)

        config = %{
          config
          | base: base,
            project: %{
              config.project
              | name: name,
                module: Module.concat([Macro.camelize(name)]),
                app: String.to_atom(name)
            }
        }

        project = generate!(dir, config)

        assert File.regular?(Path.join(project, "lib/app_#{base}_web/endpoint.ex"))
        refute File.exists?(Path.join(project, "assets"))

        refute File.exists?(
                 Path.join(project, "lib/app_#{base}_web/components/core_components.ex")
               )

        real_config = Capstone.Config.read!(Path.join(project, "target.exs"))
        assert real_config.base == base
        assert real_config.project.name == "app_#{base}"
      end
    end

    @tag :toolchain
    test "applies a real registry plugin to the project before deps.get/deps.compile",
         %{dir: dir} do
      # Same archive-restoration reason as the test above. This also needs
      # phx.new specifically, not the :otp fast path the rest of this file's
      # tests use: `Install.run/3` reads target.exs back through
      # `Capstone.Config`, which has no `:otp` value, so a plugin can only be
      # applied to a project whose base is :api, :web, or :both.
      Mix.Local.append_archives()

      registry = Path.join(dir, "registry")
      plugin_dir = Path.join(dir, "meta_probe")
      File.mkdir_p!(Path.join(plugin_dir, "files"))

      File.write!(Path.join(plugin_dir, "manifest.exs"), """
      %{name: :probe, version: "0.1.0", files: [{"README.probe.md", :sole_owner}], deps: []}
      """)

      File.write!(
        Path.join(plugin_dir, "files/README.probe.md.eex"),
        "installed by <%= @app %>\n"
      )

      {:ok, _path} = Package.run(:probe, plugin_dir, registry)

      opts =
        Factory.build(:options,
          base: :api,
          name: "app_probe",
          app: :app_probe,
          module: AppProbe,
          plugins: [:probe]
        )

      project = generate!(dir, opts, registry)

      assert File.read!(Path.join(project, "README.probe.md")) == "installed by app_probe\n"

      real_config = Capstone.Config.read!(Path.join(project, "target.exs"))
      assert real_config.plugins == [:probe]
    end
  end
end
