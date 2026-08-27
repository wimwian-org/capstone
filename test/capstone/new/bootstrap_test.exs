defmodule Capstone.New.BootstrapTest do
  # async: false — every test here changes the node-global cwd.
  use ExUnit.Case, async: false

  alias Capstone.New.Bootstrap
  alias Capstone.New.Factory

  defmodule RecordingRunner do
    @moduledoc false
    def cmd(_bin, args, opts) do
      send(self(), {:cmd, args, opts})

      {"", 0}
    end
  end

  defmodule Say do
    @moduledoc false
    def info(message), do: send(self(), {:info, message})
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "boot-#{System.unique_integer([:positive])}")
    original = File.cwd!()

    File.mkdir_p!(dir)

    on_exit(fn ->
      File.cd!(original)
      File.rm_rf!(dir)
    end)

    {:ok, dir: dir}
  end

  defp effects(dir, overrides \\ %{}) do
    Map.merge(
      %{
        getenv: fn -> %{} end,
        lookup: fn _name -> Mix.Tasks.Help end,
        generator: generator(dir, :stock_otp),
        runner: {RecordingRunner, :cmd},
        shell: Say
      },
      overrides
    )
  end

  defp generator(dir, variety) do
    fn _task, argv ->
      %{source: source} = Factory.build(:mix_exs_source, variety: variety)
      target = Path.join(dir, hd(argv))

      File.mkdir_p!(target)
      File.write!(Path.join(target, "mix.exs"), source)

      send(self(), {:generated, argv})
    end
  end

  test "run/2 drives the whole sequence with no subprocess", %{dir: dir} do
    opts = Factory.build(:options, name: "my_app", app: :my_app, module: MyApp, base: :otp)

    File.cd!(dir, fn -> assert Bootstrap.run(opts, effects(dir)) == :ok end)

    assert_received {:generated, ["my_app" | _rest]}
    assert_received {:cmd, ["deps.get"], _get_opts}
    assert_received {:cmd, ["deps.compile"], _compile_opts}
    assert_received {:info, message}
    assert message =~ "my_app"

    assert File.read!(Path.join([dir, "my_app", "mix.exs"])) =~ ":capstone"
    assert File.read!(Path.join([dir, "my_app", "target.exs"])) =~ "schema_version: 1"
  end

  test "run/2 probes the generator BEFORE any dependency work", %{dir: dir} do
    # Ordering is load-bearing: deps.compile prunes every archive off the code
    # path, so a later probe returns nil for an archive that is installed.
    opts = Factory.build(:options)

    assert_raise Mix.Error, ~r/archive\.install hex/, fn ->
      Bootstrap.run(opts, effects(dir, %{lookup: fn _name -> nil end}))
    end

    refute_received {:generated, _argv}
    refute_received {:cmd, _args, _opts}
  end

  test "run/2 refuses a poisoned parent env before creating anything", %{dir: dir} do
    opts = Factory.build(:options)
    %{env: env} = Factory.build(:env_map, poisoned: ["MIX_BUILD_PATH"])

    assert_raise Mix.Error, ~r/MIX_BUILD_PATH/, fn ->
      Bootstrap.run(opts, effects(dir, %{getenv: fn -> env end}))
    end

    refute_received {:generated, _argv}
    refute File.exists?(Path.join(dir, opts.name))
  end

  test "run/2 raises loudly when the deps anchor is absent", %{dir: dir} do
    opts = Factory.build(:options)

    File.cd!(dir, fn ->
      assert_raise Mix.Error, ~r/deps/, fn ->
        Bootstrap.run(opts, effects(dir, %{generator: generator(dir, :no_deps_block)}))
      end
    end)

    # The failure must land BEFORE any dependency work, so the half-built
    # project is never compiled against a mix.exs missing its own dep.
    refute_received {:cmd, _args, _opts}
  end

  test "run/2 raises when the project is already patched", %{dir: dir} do
    opts = Factory.build(:options)

    File.cd!(dir, fn ->
      assert_raise Mix.Error, ~r/already_patched/, fn ->
        Bootstrap.run(opts, effects(dir, %{generator: generator(dir, :already_patched)}))
      end
    end)
  end

  test "run/2 runs deps.get before deps.compile, both inside the generated project", %{dir: dir} do
    opts = Factory.build(:options, name: "my_app", app: :my_app, module: MyApp, base: :otp)

    File.cd!(dir, fn -> assert Bootstrap.run(opts, effects(dir)) == :ok end)

    assert_received {:cmd, ["deps.get"], get_opts}
    assert_received {:cmd, ["deps.compile"], compile_opts}
    assert get_opts[:cd] == "my_app"
    assert compile_opts[:cd] == "my_app"
  end

  test "defaults/0 wires the real effects as data, not closures" do
    defaults = Bootstrap.defaults()

    assert %{runner: {System, :cmd}} = defaults
    assert is_function(defaults.getenv, 0)
    assert is_function(defaults.lookup, 1)
    assert is_function(defaults.generator, 2)
    assert is_atom(defaults.shell)
  end
end
