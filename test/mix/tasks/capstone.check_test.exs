defmodule Mix.Tasks.Capstone.CheckTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Capstone.Manifest
  alias Capstone.Plugin.Apply
  alias Capstone.Root
  alias Mix.Tasks.Capstone.Check
  alias Mix.Tasks.Capstone.Plugin.Apply, as: ApplyTask

  setup do
    dir = Path.join(System.tmp_dir!(), "check-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "lib"))
    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, dir: dir}
  end

  describe "capstone.check" do
    test "passes on a tree with no markers", %{dir: dir} do
      File.write!(Path.join(dir, "lib/app.ex"), "defmodule App do\nend\n")

      assert capture_io(fn -> Check.run([dir]) end) =~ "no unresolved"
    end

    test "fails while a marker remains, naming the file and key", %{dir: dir} do
      File.write!(Path.join(dir, "lib/app.ex"), "x\n#{Apply.marker_prefix(:cache_app)}\ny\n")

      assert_raise Mix.Error, ~r/lib\/app\.ex.*cache_app/s, fn -> Check.run([dir]) end
    end

    test "skips binary files rather than raising on them", %{dir: dir} do
      # A plugin payload may include an icon; String.contains?/2 on invalid
      # UTF-8 would blow up the gate rather than report on it.
      File.write!(Path.join(dir, "lib/icon.png"), <<137, 80, 78, 71, 13, 10, 26, 10>>)

      assert capture_io(fn -> Check.run([dir]) end) =~ "no unresolved"
    end

    test "defaults to the current directory" do
      # Asserted by equivalence, not by outcome. Upstream asserted both raised,
      # because that repo's plan documents carry example markers in their code
      # blocks and its tree is therefore never clean. This tree is clean, so the
      # same assertion inverted would be just as brittle -- what the task
      # actually promises is that no argument means ".".
      assert capture_io(fn -> Check.run([]) end) == capture_io(fn -> Check.run(["."]) end)
    end
  end

  describe "capstone.plugin.apply" do
    test "both tasks expose a @shortdoc" do
      assert Mix.Task.shortdoc(Check) =~ "unresolved"
      assert Mix.Task.shortdoc(ApplyTask) =~ "derived plugin"
    end

    test "applies a plugin and reports the positional entries", %{dir: dir} do
      target = Path.join(dir, "target")
      File.cp_r!("priv/meta/baseline_api", target)

      output = capture_io(fn -> ApplyTask.run(["cache", target]) end)

      assert output =~ "applied cache to #{target}: 6 files"
      assert output =~ "positional entr(ies): [:cache_app]"
      assert File.exists?(Path.join(target, "lib/new_api_app/cache.ex"))
    end

    test "an underived plugin names the task that would create it", %{dir: dir} do
      assert_raise Mix.Error, ~r/run mix capstone\.plugin\.derive nosuch/, fn ->
        ApplyTask.run(["nosuch", dir])
      end
    end

    test "a missing target is refused" do
      assert_raise Mix.Error, ~r/does not exist/, fn ->
        ApplyTask.run(["cache", "/nonexistent/target"])
      end
    end

    test "run/1 requires a plugin name and a target" do
      assert_raise Mix.Error, ~r/expects a plugin name and a target/, fn ->
        ApplyTask.run(["cache"])
      end
    end

    test "reports an untracked target, and records nothing", %{dir: dir} do
      target = Path.join(dir, "plain")
      File.cp_r!("priv/meta/baseline_api", target)

      output = capture_io(fn -> ApplyTask.run(["cache", target]) end)

      assert output =~ "not a Capstone project — no target.exs, so nothing was recorded."
      assert output =~ "add one to make this project updatable."
      refute File.exists?(Path.join(target, "plugin.exs"))
    end

    test "says nothing about recording when the target is declared", %{dir: dir} do
      target = Path.join(dir, "declared")
      File.cp_r!("priv/meta/baseline_api", target)
      declared = Root.new!(target)

      # A minimal target.exs valid against this package's own Capstone.Config
      # (base: :api/:web/:both -- not the umbrella's :otp/:api/:web -- and no
      # :config_map factory here, since that fixture is shaped for the
      # excluded 14-module schema).
      File.write!(
        Root.path(declared, "target.exs"),
        ~s"""
        %{
          schema_version: 1,
          base: :api,
          plugins: [],
          project: [name: "widgets", github_org: "acme"]
        }
        """
      )

      output = capture_io(fn -> ApplyTask.run(["cache", target]) end)

      refute output =~ "not a Capstone project"
      assert [entry] = Manifest.read!(declared).plugins
      assert entry.name == :cache
    end
  end
end
