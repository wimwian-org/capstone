defmodule Mix.Tasks.Capstone.UpdateTest do
  @moduledoc """
  Every test here seeds its fixture archive into a `tmp_dir`-scoped registry
  handed to `Task.run/3`, never into `Capstone.Plugin.Registry.default_dir/0`
  — the real, machine-global OS cache directory shared across every project
  using `capstone` and across test runs, not something a test should write
  fixtures into or read stale state from.

  Each test also fakes the `sync` effect: `:probe` is never actually
  published, so the real `Capstone.Plugin.Remote.sync!/2` would just be an
  incidental, unnecessary network round-trip for every run.
  """

  use ExUnit.Case, async: false

  alias Capstone.Plugin.Package
  alias Mix.Tasks.Capstone.Update, as: Task

  defp no_sync, do: fn _type, _dir -> :ok end

  @tag :tmp_dir
  test "updates the target given as the sole argument", %{tmp_dir: tmp} do
    registry = Path.join(tmp, "registry")
    target = Path.join(tmp, "target")
    File.mkdir_p!(target)

    File.write!(Path.join(target, "mix.exs"), """
    defmodule MyApp.MixProject do
      use Mix.Project
      def project, do: [app: :my_app, version: "0.1.0", elixir: "~> 1.20", deps: deps()]
      defp deps, do: []
    end
    """)

    File.write!(Path.join(target, "target.exs"), """
    %{schema_version: 1, base: :api, plugins: [:probe],
      project: [name: "my_app", github_org: "acme"]}
    """)

    plugin_dir = Path.join(tmp, "meta_probe")
    File.mkdir_p!(Path.join(plugin_dir, "files"))

    File.write!(Path.join(plugin_dir, "manifest.exs"), """
    %{name: :probe, version: "0.1.0", files: [{"README.probe.md", :sole_owner}], deps: []}
    """)

    File.write!(Path.join(plugin_dir, "files/README.probe.md.eex"), "installed by <%= @app %>\n")
    {:ok, _path} = Package.run(:probe, plugin_dir, registry)

    File.cd!(tmp, fn -> Task.run([target], registry, no_sync()) end)

    assert File.read!(Path.join(target, "README.probe.md")) == "installed by my_app\n"
  end

  @tag :tmp_dir
  test "updates current directory when no target is given", %{tmp_dir: tmp} do
    registry = Path.join(tmp, "registry")

    File.write!(Path.join(tmp, "mix.exs"), """
    defmodule MyApp.MixProject do
      use Mix.Project
      def project, do: [app: :my_app, version: "0.1.0", elixir: "~> 1.20", deps: deps()]
      defp deps, do: []
    end
    """)

    File.write!(Path.join(tmp, "target.exs"), """
    %{schema_version: 1, base: :api, plugins: [:probe],
      project: [name: "my_app", github_org: "acme"]}
    """)

    plugin_dir = Path.join(tmp, "meta_probe")
    File.mkdir_p!(Path.join(plugin_dir, "files"))

    File.write!(Path.join(plugin_dir, "manifest.exs"), """
    %{name: :probe, version: "0.1.0", files: [{"README.probe.md", :sole_owner}], deps: []}
    """)

    File.write!(Path.join(plugin_dir, "files/README.probe.md.eex"), "installed by <%= @app %>\n")
    {:ok, _path} = Package.run(:probe, plugin_dir, registry)

    File.cd!(tmp, fn -> Task.run([], registry, no_sync()) end)

    assert File.read!(Path.join(tmp, "README.probe.md")) == "installed by my_app\n"
  end

  @tag :tmp_dir
  test "prints nothing new to apply when all plugins are already applied", %{tmp_dir: tmp} do
    registry = Path.join(tmp, "registry")
    target = Path.join(tmp, "target")
    File.mkdir_p!(target)

    File.write!(Path.join(target, "mix.exs"), """
    defmodule MyApp.MixProject do
      use Mix.Project
      def project, do: [app: :my_app, version: "0.1.0", elixir: "~> 1.20", deps: deps()]
      defp deps, do: []
    end
    """)

    File.write!(Path.join(target, "target.exs"), """
    %{schema_version: 1, base: :api, plugins: [:probe],
      project: [name: "my_app", github_org: "acme"]}
    """)

    plugin_dir = Path.join(tmp, "meta_probe")
    File.mkdir_p!(Path.join(plugin_dir, "files"))

    File.write!(Path.join(plugin_dir, "manifest.exs"), """
    %{name: :probe, version: "0.1.0", files: [{"README.probe.md", :sole_owner}], deps: []}
    """)

    File.write!(Path.join(plugin_dir, "files/README.probe.md.eex"), "installed by <%= @app %>\n")
    {:ok, _path} = Package.run(:probe, plugin_dir, registry)

    # First run applies the plugin
    File.cd!(tmp, fn -> Task.run([target], registry, no_sync()) end)

    # Second run should say nothing new to apply
    File.cd!(tmp, fn -> Task.run([target], registry, no_sync()) end)

    assert File.read!(Path.join(target, "README.probe.md")) == "installed by my_app\n"
  end

  test "raises on more than one argument" do
    assert_raise Mix.Error, ~r/expects at most one target/, fn -> Task.run(["a", "b"]) end
  end
end
