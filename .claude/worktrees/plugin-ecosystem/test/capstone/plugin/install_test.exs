defmodule Capstone.Plugin.InstallTest do
  use ExUnit.Case, async: false

  alias Capstone.Plugin.Install
  alias Capstone.Plugin.Package

  @tag :tmp_dir
  test "resolves, extracts, applies, and records a registry archive", %{tmp_dir: tmp} do
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
    %{schema_version: 1, base: :api, plugins: [], project: [name: "my_app", github_org: "acme"]}
    """)

    plugin_dir = Path.join(tmp, "meta_probe")
    File.mkdir_p!(Path.join(plugin_dir, "files"))

    File.write!(Path.join(plugin_dir, "manifest.exs"), """
    %{name: :probe, version: "0.1.0", files: [{"README.probe.md", :sole_owner}], deps: []}
    """)

    File.write!(Path.join(plugin_dir, "files/README.probe.md.eex"), "installed by <%= @app %>\n")

    {:ok, _path} = Package.run(:probe, plugin_dir, registry)

    before = File.ls!(System.tmp_dir!())
    {:ok, _plugin} = Install.run(:probe, target, registry)
    after_success = File.ls!(System.tmp_dir!())

    assert File.read!(Path.join(target, "README.probe.md")) == "installed by my_app\n"

    manifest = Capstone.Manifest.read!(Capstone.Root.new!(target))
    [entry] = manifest.plugins
    assert entry.name == :probe
    assert {:registry, filename} = entry.origin
    assert String.starts_with?(filename, "probe-")

    # Verify no temp directory was left behind on success
    assert after_success -- before == []
  end

  @tag :tmp_dir
  test "leaves no temp directory behind on success or failure", %{tmp_dir: tmp} do
    registry = Path.join(tmp, "registry")
    File.mkdir_p!(registry)
    before = File.ls!(System.tmp_dir!())

    assert_raise Mix.Error, fn -> Install.run(:nosuch, tmp, registry) end

    assert File.ls!(System.tmp_dir!()) -- before == []
  end
end
