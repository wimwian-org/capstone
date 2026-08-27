defmodule Capstone.UpdateTest do
  use ExUnit.Case, async: false

  alias Capstone.Plugin.Package
  alias Capstone.Update

  @tag :tmp_dir
  test "applies only the plugin newly listed in target.exs", %{tmp_dir: tmp} do
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

    assert {:ok, [:probe]} = Update.run(target, registry)
    assert File.read!(Path.join(target, "README.probe.md")) == "installed by my_app\n"
  end

  @tag :tmp_dir
  test "an already-recorded plugin is left untouched", %{tmp_dir: tmp} do
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

    assert {:ok, [:probe]} = Update.run(target, registry)
    File.write!(Path.join(target, "README.probe.md"), "hand-edited\n")

    assert {:ok, []} = Update.run(target, registry)
    assert File.read!(Path.join(target, "README.probe.md")) == "hand-edited\n"
  end

  @tag :tmp_dir
  test "no target.exs means no plugins to apply" do
    tmp = tmp_project_without_target_exs()
    assert {:ok, []} = Update.run(tmp, "unused")
  end

  defp tmp_project_without_target_exs do
    unique = System.unique_integer([:positive])
    dir = Path.join(System.tmp_dir!(), "capstone_update_notarget_#{unique}")
    File.mkdir_p!(dir)

    File.write!(
      Path.join(dir, "mix.exs"),
      "defmodule X.MixProject do\n  use Mix.Project\n  def project, do: [app: :x, version: \"0.1.0\"]\nend\n"
    )

    dir
  end
end
