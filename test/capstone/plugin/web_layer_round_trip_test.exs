defmodule Capstone.Plugin.WebLayerRoundTripTest do
  # async: false — copies real trees under priv/meta.
  use ExUnit.Case, async: false

  alias Capstone.Baseline
  alias Capstone.Plugin.Apply

  @baseline "priv/meta/baseline_api"
  @plugin "priv/meta/meta_web_layer"
  @raw "priv/meta/web_component"

  setup do
    target =
      Path.join(System.tmp_dir!(), "web-layer-round-trip-#{System.unique_integer([:positive])}")

    File.cp_r!(@baseline, target)
    on_exit(fn -> File.rm_rf!(target) end)

    {:ok, target: target}
  end

  test "applying meta_web_layer to baseline_api reproduces web_component", %{target: target} do
    {:ok, _plugin} = Apply.run(@plugin, target)

    expected = Baseline.tree(@raw)
    actual = Baseline.tree(target)

    differing = for {path, hash} <- expected, actual[path] != hash, do: path

    assert differing == []
    assert Enum.sort(Map.keys(actual)) == Enum.sort(Map.keys(expected))
  end

  test "applying twice is a no-op", %{target: target} do
    {:ok, _} = Apply.run(@plugin, target)
    once = Baseline.tree(target)

    {:ok, _} = Apply.run(@plugin, target)

    assert Baseline.tree(target) == once
  end

  test "the plugin installs into a differently named project" do
    other = Path.join(System.tmp_dir!(), "web-layer-other-#{System.unique_integer([:positive])}")
    File.cp_r!(@baseline, other)
    on_exit(fn -> File.rm_rf!(other) end)

    mix = Path.join(other, "mix.exs")
    File.write!(mix, String.replace(File.read!(mix), ":new_api_app", ":other_app"))

    root = Path.join(other, "lib/new_api_app.ex")

    File.write!(
      Path.join(other, "lib/other_app.ex"),
      String.replace(File.read!(root), "NewApiApp", "OtherApp")
    )

    File.rm!(root)
    File.rename!(Path.join(other, "lib/new_api_app"), Path.join(other, "lib/other_app"))

    web_root = Path.join(other, "lib/new_api_app_web.ex")

    File.write!(
      Path.join(other, "lib/other_app_web.ex"),
      String.replace(File.read!(web_root), "NewApiAppWeb", "OtherAppWeb")
    )

    File.rm!(web_root)
    File.rename!(Path.join(other, "lib/new_api_app_web"), Path.join(other, "lib/other_app_web"))

    for file <- Path.wildcard(Path.join(other, "lib/other_app/**/*.ex")) do
      File.write!(file, String.replace(File.read!(file), "NewApiApp", "OtherApp"))
    end

    for file <- Path.wildcard(Path.join(other, "lib/other_app_web/**/*.{ex,heex}")) do
      File.write!(file, String.replace(File.read!(file), "NewApiAppWeb", "OtherAppWeb"))
    end

    {:ok, _} = Apply.run(@plugin, other)

    # Verify :sole_owner files exist and old ones don't
    assert File.exists?(Path.join(other, "lib/other_app/vite_watcher.ex"))
    refute File.exists?(Path.join(other, "lib/new_api_app/vite_watcher.ex"))

    # Verify content-rewrite of :manual hunks actually happened
    router_content = File.read!(Path.join(other, "lib/other_app_web/router.ex"))
    assert router_content =~ "defmodule OtherAppWeb.Router do"
    refute router_content =~ "NewApiAppWeb"
    refute router_content =~ Apply.marker_prefix(:web_layer_router)

    endpoint_content = File.read!(Path.join(other, "lib/other_app_web/endpoint.ex"))
    assert endpoint_content =~ "defmodule OtherAppWeb.Endpoint do"
    refute endpoint_content =~ "NewApiAppWeb"
    refute endpoint_content =~ Apply.marker_prefix(:web_layer_endpoint)
  end
end
