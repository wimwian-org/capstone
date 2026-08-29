defmodule Capstone.Plugin.OpenbaoRoundTripTest do
  # async: false — copies real trees under priv/meta.
  use ExUnit.Case, async: false

  alias Capstone.Baseline
  alias Capstone.Plugin.Apply

  @baseline "priv/meta/baseline_api"
  @plugin "priv/meta/meta_openbao"
  @raw "priv/meta/openbao_component"

  setup do
    target =
      Path.join(System.tmp_dir!(), "openbao-round-trip-#{System.unique_integer([:positive])}")

    File.cp_r!(@baseline, target)
    on_exit(fn -> File.rm_rf!(target) end)

    {:ok, target: target}
  end

  test "applying meta_openbao to baseline_api reproduces openbao_component", %{target: target} do
    {:ok, _component} = Apply.run(@plugin, target)

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
    other = Path.join(System.tmp_dir!(), "openbao-other-#{System.unique_integer([:positive])}")
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

    for file <- Path.wildcard(Path.join(other, "lib/other_app/**/*.ex")) do
      File.write!(file, String.replace(File.read!(file), "NewApiApp", "OtherApp"))
    end

    {:ok, _} = Apply.run(@plugin, other)

    assert File.read!(Path.join(other, "lib/other_app/vault.ex")) =~
             "defmodule OtherApp.Vault"

    assert File.read!(Path.join(other, "config/runtime.exs")) =~
             "config :other_app, OtherApp.Vault"

    refute File.exists?(Path.join(other, "lib/new_api_app/vault.ex"))
  end
end
