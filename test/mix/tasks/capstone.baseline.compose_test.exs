defmodule Mix.Tasks.Capstone.Baseline.ComposeTest do
  # async: false — one test below rewrites priv/baselines.exs inside the
  # repository working directory.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Capstone.Baseline
  alias Mix.Tasks.Capstone.Baseline.Compose

  describe "composing a synthetic entry" do
    # No release entry carries BOTH plugin: and derived_from: this release --
    # :web (api + web_layer) is the only one Compose was built for, and it is
    # not part of this release's baselines.exs. Injecting api + openapi (a
    # real derived_from: :api lineage that already ships) into a scratch
    # manifest entry exercises the same rename-then-apply path without
    # depending on a fixture this release does not carry.
    setup do
      manifest = File.read!("priv/baselines.exs")
      api = Baseline.read!("priv/baselines.exs").api
      dir = Path.join(System.tmp_dir!(), "compose-#{System.unique_integer([:positive])}")
      entry = Map.merge(api, %{path: dir, plugin: :openapi, derived_from: :api})

      File.write!(
        "priv/baselines.exs",
        String.replace(manifest, "  api: %{", "  probe: #{inspect(entry)},\n  api: %{",
          global: false
        )
      )

      on_exit(fn ->
        File.write!("priv/baselines.exs", manifest)
        File.rm_rf!(dir)
      end)

      {:ok, dir: dir}
    end

    test "composes the entry's tree from its baseline plus its plugin", %{dir: dir} do
      output = capture_io(fn -> Compose.run(["probe"]) end)

      assert output =~ "composed #{dir} from priv/meta/baseline_api + priv/meta/meta_openapi"
      assert File.exists?(Path.join(dir, "lib/new_api_app_web/api_spec.ex"))
    end

    test "the composed tree carries the layer the plugin contributes", %{dir: dir} do
      capture_io(fn -> Compose.run(["probe"]) end)

      assert File.exists?(Path.join(dir, "lib/new_api_app_web/schemas.ex"))
      assert File.read!(Path.join(dir, "lib/new_api_app_web/router.ex")) =~ "OpenApiSpex"
    end

    test "a binary asset survives the rename unmodified", %{dir: dir} do
      # `Template.capture/2` refuses non-UTF-8 bytes, so the rename has to
      # take a verbatim path for them or the composition loses every image
      # and font.
      source = File.read!("priv/meta/baseline_api/priv/static/favicon.ico")

      capture_io(fn -> Compose.run(["probe"]) end)

      assert File.read!(Path.join(dir, "priv/static/favicon.ico")) == source
    end

    test "it is deterministic", %{dir: dir} do
      capture_io(fn -> Compose.run(["probe"]) end)
      first = Baseline.digest(dir)

      capture_io(fn -> Compose.run(["probe"]) end)

      assert Baseline.digest(dir) == first
    end
  end

  test "an entry with no plugin is refused" do
    assert_raise Mix.Error, ~r/no plugin:/, fn ->
      Compose.run(["api"])
    end
  end

  test "an entry naming a plugin but no source is refused" do
    # A malformed manifest, and the reason both keys are validated BEFORE
    # either is dereferenced: without it this raises a KeyError naming a key
    # the message never mentions.
    manifest = File.read!("priv/baselines.exs")
    on_exit(fn -> File.write!("priv/baselines.exs", manifest) end)

    File.write!(
      "priv/baselines.exs",
      String.replace(
        manifest,
        "  api: %{",
        "  orphan: %{plugin: :openapi, path: \"priv/meta/orphan\"},\n  api: %{",
        global: false
      )
    )

    assert_raise Mix.Error, ~r/no derived_from:/, fn -> Compose.run(["orphan"]) end
  end

  test "an unknown name is refused" do
    assert_raise Mix.Error, ~r/no entry/, fn ->
      Compose.run(["nope"])
    end
  end

  test "it expects exactly one name" do
    assert_raise Mix.Error, ~r/expects one entry name/, fn ->
      Compose.run([])
    end
  end
end
