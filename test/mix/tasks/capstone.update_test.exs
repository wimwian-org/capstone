defmodule Mix.Tasks.Capstone.UpdateTest do
  @moduledoc """
  Every test here seeds its fixture archive into a `tmp_dir`-scoped registry
  handed to `Task.run/2`, never into `Capstone.Plugin.Registry.default_dir/0`.

  That is load-bearing rather than tidy: under `MIX_ENV=test`
  `_build/test/lib/capstone/priv` is a SYMLINK to this repository's own
  `priv/`, and `priv/plugins/` is in `mix.exs`'s `package.files`. A test
  packaging into `default_dir/0` therefore writes a junk archive straight into
  the checked-in, hex-shipped registry, where `mix test && mix hex.publish`
  would ship it to every consumer.
  """

  use ExUnit.Case, async: false

  alias Capstone.Plugin.Package
  alias Mix.Tasks.Capstone.Update, as: Task

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

    File.cd!(tmp, fn -> Task.run([target], registry) end)

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

    File.cd!(tmp, fn -> Task.run([], registry) end)

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
    File.cd!(tmp, fn -> Task.run([target], registry) end)

    # Second run should say nothing new to apply
    File.cd!(tmp, fn -> Task.run([target], registry) end)

    assert File.read!(Path.join(target, "README.probe.md")) == "installed by my_app\n"
  end

  test "raises on more than one argument" do
    assert_raise Mix.Error, ~r/expects at most one target/, fn -> Task.run(["a", "b"]) end
  end
end
