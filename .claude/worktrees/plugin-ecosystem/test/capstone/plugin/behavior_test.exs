defmodule Capstone.Plugin.BehaviorTest do
  @moduledoc """
  Exercises the public plugin contract.

  Fixtures are compiled with `Code.compile_string/1` inside each test rather
  than declared at the top of the file. That is deliberate: `use Capstone.Plugin.Behavior`
  does its validation at **compile** time, so a fixture declared normally would
  be expanded while this file is being loaded — before the assertions run, and
  outside the coverage the suite measures.
  """

  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  describe "a minimal plugin" do
    setup do
      {:ok,
       plugin:
         compile(~s|use Capstone.Plugin.Behavior, name: :cache, version: "1.3.0"|, files: true)}
    end

    test "takes its identity from the use options", %{plugin: plugin} do
      assert plugin.name() == :cache
      assert plugin.version() == "1.3.0"
    end

    test "gets empty defaults for everything optional", %{plugin: plugin} do
      assert plugin.deps() == []
      assert plugin.requires() == []
      assert plugin.provides() == []
      assert plugin.conflicts() == []
    end

    test "declares the behaviour", %{plugin: plugin} do
      assert Capstone.Plugin.Behavior in plugin.module_info(:attributes)[:behaviour]
    end

    test "returns its own file list", %{plugin: plugin} do
      assert plugin.files(%{}) == [{"lib/APP/thing.ex", :sole_owner}]
    end
  end

  describe "overriding the defaults" do
    test "a plugin may replace any of the four defaulted callbacks" do
      plugin =
        compile(
          """
          use Capstone.Plugin.Behavior, name: :valkey, version: "1.3.0"

          @impl true
          def deps, do: [{:nebulex, "~> 3.0"}]

          @impl true
          def requires, do: [:container_runtime]

          @impl true
          def provides, do: [:durable_cache]

          @impl true
          def conflicts, do: [:memcached]
          """,
          files: true
        )

      assert plugin.deps() == [{:nebulex, "~> 3.0"}]
      assert plugin.requires() == [:container_runtime]
      assert plugin.provides() == [:durable_cache]
      assert plugin.conflicts() == [:memcached]
    end
  end

  describe "the optional escape hatches" do
    test "a plugin without transform/2 or upgrade/3 compiles clean" do
      warnings =
        capture_io(:stderr, fn ->
          compile(~s|use Capstone.Plugin.Behavior, name: :cache, version: "1.0.0"|, files: true)
        end)

      refute warnings =~ "transform/2"
      refute warnings =~ "upgrade/3"
    end

    test "a plugin may implement them" do
      plugin =
        compile(
          """
          use Capstone.Plugin.Behavior, name: :cache, version: "1.0.0"

          @impl true
          def transform(_root, _config), do: :ok

          @impl true
          def upgrade(_root, _from, _to), do: :ok
          """,
          files: true
        )

      assert plugin.transform("/tmp/project", %{}) == :ok
      assert plugin.upgrade("/tmp/project", "1.0.0", "1.1.0") == :ok
    end
  end

  describe "compile-time validation" do
    test "omitting files/1 is reported, because nothing else would catch it" do
      warnings =
        capture_io(:stderr, fn ->
          compile(~s|use Capstone.Plugin.Behavior, name: :cache, version: "1.0.0"|, files: false)
        end)

      assert warnings =~ "files/1"
    end

    test "a missing :name fails at build time, not at install time" do
      assert_raise ArgumentError, ~r/requires :name/, fn ->
        compile(~s|use Capstone.Plugin.Behavior, version: "1.0.0"|, files: true)
      end
    end

    test "a missing :version fails at build time" do
      assert_raise ArgumentError, ~r/requires :version/, fn ->
        compile(~s|use Capstone.Plugin.Behavior, name: :cache|, files: true)
      end
    end

    # D5 -- Fireside's integer scheme could not express a range, and choosing
    # semver is what keeps delegating upgrades an option later.
    test "a non-semver version string is refused" do
      assert_raise ArgumentError, ~r/semver/, fn ->
        compile(~s|use Capstone.Plugin.Behavior, name: :cache, version: "1.3"|, files: true)
      end
    end

    test "an integer version is refused" do
      assert_raise ArgumentError, ~r/semver/, fn ->
        compile(~s|use Capstone.Plugin.Behavior, name: :cache, version: 3|, files: true)
      end
    end
  end

  describe "the ownership mode enum" do
    # SimpleEnum's macros resolve at compile time, so they have to be imported
    # into the calling module rather than called as `Capstone.Plugin.Behavior.mode(...)`.
    import Capstone.Plugin.Behavior

    test "names exactly the three ownership modes" do
      assert mode_keys() == [:sole_owner, :contributes, :seed]
    end

    test "looks up bidirectionally" do
      assert mode(:contributes) == 1
      assert mode(1) == :contributes
      assert mode(:seed, :tuple) == {:seed, 2}
    end

    test "guards membership, which is what a manifest loader needs" do
      # D20 lets a plugin ship as data with no compile step, so a typo in its
      # `mode` has to be caught at load time. A bare union type cannot do that.
      assert is_mode_key(:sole_owner)
      refute is_mode_key(:sole_ownr)
      refute is_mode_key(:overwritable)
    end

    test "an unknown mode raises, and names the valid ones" do
      # Measured, not assumed: an unrecognised literal does NOT fail the
      # compile. SimpleEnum falls back to a runtime lookup, so the failure
      # arrives when the call is made. That is why `is_mode_key/1` above is the
      # thing a loader should reach for, rather than trusting `mode/1` to reject
      # bad data early.
      [{module, _bytecode}] =
        Code.compile_string("""
        defmodule ModeFixture#{System.unique_integer([:positive])} do
          @moduledoc false
          import Capstone.Plugin.Behavior
          def bad, do: mode(:overwritable)
        end
        """)

      message = assert_raise(ArgumentError, fn -> module.bad() end).message

      assert message =~ ":overwritable"
      assert message =~ ":sole_owner"
    end
  end

  defp compile(body, files: files?) do
    module = :"Elixir.PluginFixture#{System.unique_integer([:positive])}"

    files =
      if files? do
        """
        @impl true
        def files(_config), do: [{"lib/APP/thing.ex", :sole_owner}]
        """
      else
        ""
      end

    source = """
    defmodule #{inspect(module)} do
      @moduledoc false
      #{body}
      #{files}
    end
    """

    [{^module, _bytecode}] = Code.compile_string(source)
    module
  end
end
