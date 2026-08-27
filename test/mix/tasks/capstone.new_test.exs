defmodule Mix.Tasks.Capstone.NewTest do
  use ExUnit.Case, async: true

  alias Capstone.New.Bootstrap
  alias Capstone.New.Factory
  alias Capstone.New.Options
  alias Capstone.New.TargetExsFixture
  alias Mix.Tasks.Capstone.New

  defp write_target_exs!(config) do
    path = Path.join(System.tmp_dir!(), "target-#{System.unique_integer([:positive])}.exs")
    File.write!(path, TargetExsFixture.render(config))
    on_exit(fn -> File.rm!(path) end)
    path
  end

  test "run/1 validates argv before doing anything else" do
    # The ordering is the assertion. Validating late would let a missing
    # --path through to Bootstrap, moving a class of failure to after a
    # project directory already exists on disk.
    assert_raise Options.Error, ~r/--path is required/, fn -> New.run([]) end
  end

  test "run/1 creates nothing when argv is invalid" do
    before = File.ls!()

    assert_raise Options.Error, fn -> New.run(["extra"]) end

    assert File.ls!() == before
  end

  test "run/1 surfaces Capstone.Config.Error for an invalid target.exs, creating nothing" do
    path = write_target_exs!(Factory.build(:config))
    File.write!(path, "%{}")
    before = File.ls!()

    assert_raise Capstone.Config.Error, fn -> New.run(["--path", path]) end

    assert File.ls!() == before
  end

  test "the task is discoverable under the name the archive advertises" do
    assert Mix.Task.task_name(New) == "capstone.new"
    assert Mix.Task.shortdoc(New) =~ "Capstone"
  end

  test "run/1 is a shim: it delegates rather than reimplementing the sequence" do
    # The whole coverage seam rests on run/1 staying two lines. If the sequence
    # were ever inlined back into it, 12 of 14 relevant lines would become
    # reachable only from a :toolchain test that the coverage run excludes —
    # which is how the 100% coverage gate would silently stop meaning anything.
    source = File.read!("lib/mix/tasks/capstone.new.ex")

    assert source =~ "Bootstrap.run("
    refute source =~ "System.cmd"
    refute source =~ "File.write!"
  end

  test "the ignored span covers only the shim body" do
    source = File.read!("lib/mix/tasks/capstone.new.ex")
    lines = String.split(source, "\n")

    start = Enum.find_index(lines, &(&1 =~ "coveralls-ignore-start"))
    stop = Enum.find_index(lines, &(&1 =~ "coveralls-ignore-stop"))

    assert start && stop
    assert stop - start <= 8, "the ignore span has grown to #{stop - start} lines"
  end

  test "defaults/0 is what the shim hands the bootstrap" do
    # Pins the wiring the shim itself cannot have a coverage test for.
    assert %{runner: {System, :cmd}} = Bootstrap.defaults()
  end
end
