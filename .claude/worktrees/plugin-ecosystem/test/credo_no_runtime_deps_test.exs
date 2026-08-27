defmodule CredoNoRuntimeDepsTest do
  @moduledoc """
  Pins the rule that keeps Capstone out of its target's dependency graph.

  Capstone is installed as a dev dependency inside someone else's project, so any
  requirement it declares for `:prod` becomes a constraint on that project's
  resolution. The rule is `only:` excluding `:prod`, and the trap this guards
  is that **`runtime: false` looks like it does the same job and does not** —
  it controls the boot sequence, not the graph.

  Today `mix.exs` satisfies this trivially: every dependency is Capstone's own
  toolchain. The check exists for the first time someone reaches for Sourceror
  as an ordinary dependency instead of vendoring it.
  """

  use ExUnit.Case, async: true

  alias Capstone.Credo.Check.Design.NoRuntimeDeps
  alias Credo.SourceFile

  @mix_exs Path.expand("../mix.exs", __DIR__)

  setup_all do
    {:ok, _apps} = Application.ensure_all_started(:credo)

    :ok
  end

  describe "dependencies that reach the target's graph" do
    test "a bare requirement is flagged" do
      assert [issue] = check(~s|{:sourceror, "~> 1.12"}|)
      assert issue.message =~ ":sourceror"
      assert issue.trigger == "sourceror"
    end

    test "runtime: false alone is NOT enough" do
      # The whole point of the check. `runtime: false` stops the application
      # being started; hex still resolves the dependency and still propagates
      # it to dependents.
      assert [issue] = check(~s|{:sourceror, "~> 1.12", runtime: false}|)
      assert issue.message =~ "runtime: false is not enough"
    end

    test "an only: that includes :prod is flagged" do
      assert [_issue] = check(~s|{:sourceror, "~> 1.12", only: [:dev, :prod]}|)
    end

    test "a path dependency without only: is flagged" do
      assert [_issue] = check(~s|{:vendored, path: "../vendored"}|)
    end

    test "an only: that cannot be read as a literal is flagged" do
      # A dependency whose scope cannot be proven is exactly the one to look at.
      assert [_issue] = check(~s|{:sourceror, "~> 1.12", only: @envs}|)
    end

    test "every offender in the list is reported" do
      assert [_one, _two] =
               check(~s|{:sourceror, "~> 1.12"}, {:vex, "~> 0.9"}|)
    end
  end

  describe "dependencies invisible to the target" do
    test "only: [:dev, :test] with runtime: false passes" do
      assert check(~s|{:credo, "~> 1.7", only: [:dev, :test], runtime: false}|) == []
    end

    test "a bare atom only: passes" do
      assert check(~s|{:doctor, "~> 0.22", only: :dev, runtime: false}|) == []
      assert check(~s|{:excoveralls, "~> 0.18", only: :test}|) == []
    end

    test "an empty dependency list passes" do
      assert check("") == []
    end
  end

  describe "scope" do
    test "def deps is checked as well as defp deps" do
      source = """
      defmodule Probe.MixProject do
        def deps do
          [{:sourceror, "~> 1.12"}]
        end
      end
      """

      assert [_issue] = run_on(source, "mix.exs")
    end

    test "a file that is not mix.exs is ignored" do
      source = """
      defmodule Probe do
        defp deps, do: [{:sourceror, "~> 1.12"}]
      end
      """

      assert run_on(source, "lib/probe.ex") == []
    end
  end

  describe "the real mix.exs" do
    test "declares no dependency that would constrain a target project" do
      issues =
        @mix_exs
        |> File.read!()
        |> SourceFile.parse("mix.exs")
        |> NoRuntimeDeps.run([])

      assert issues == [],
             "offending deps: " <> Enum.map_join(issues, ", ", & &1.trigger)
    end
  end

  defp check(entries) do
    run_on(
      """
      defmodule Probe.MixProject do
        defp deps do
          [#{entries}]
        end
      end
      """,
      "mix.exs"
    )
  end

  defp run_on(source, filename) do
    source
    |> SourceFile.parse(filename)
    |> NoRuntimeDeps.run([])
  end
end
