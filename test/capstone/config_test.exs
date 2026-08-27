defmodule Capstone.ConfigTest do
  use ExUnit.Case, async: true

  import Capstone.New.Factory

  alias Capstone.Config
  alias Capstone.New.TargetExsFixture

  describe "read_string/1 — valid input round-trips" do
    test "a factory-built config renders and re-parses to itself" do
      config = build(:config)
      source = TargetExsFixture.render(config)

      assert Config.read_string(source) == {:ok, config}
    end

    test "a config with every non-default value set round-trips too" do
      config = %{
        build(:config)
        | base: :api,
          security: %Capstone.Config.Security{envelope_encryption: true, cloak: true},
          container: %Capstone.Config.Container{
            local_ci: false,
            sidecars: %Capstone.Config.Container.Sidecars{
              valkey: true,
              openbao: true,
              nginx: true
            }
          }
      }

      source = TargetExsFixture.render(config)

      assert Config.read_string(source) == {:ok, config}
    end

    test "base: :both also round-trips" do
      config = %{build(:config) | base: :both}
      source = TargetExsFixture.render(config)

      assert Config.read_string(source) == {:ok, config}
    end

    test "security and container may be omitted entirely, defaulting" do
      config = build(:config)

      source = """
      %{
        schema_version: 1,
        base: :web,
        plugins: [],
        project: [name: #{inspect(config.project.name)}, github_org: #{inspect(config.project.github_org)}]
      }
      """

      assert {:ok, result} = Config.read_string(source)
      assert result.security == %Capstone.Config.Security{}
      assert result.container == %Capstone.Config.Container{}
    end
  end

  describe "read_string/1 — top-level structure" do
    test "rejects a non-map top-level term" do
      assert Config.read_string("[1, 2, 3]") == {:error, [{:not_a_map, [1, 2, 3]}]}
    end

    test "reports every missing required key at once" do
      assert {:error, errors} = Config.read_string("%{}")
      assert {:missing_key, [:schema_version]} in errors
      assert {:missing_key, [:base]} in errors
      assert {:missing_key, [:plugins]} in errors
      assert {:missing_key, [:project]} in errors
    end

    test "reports an unknown top-level key" do
      source = """
      %{schema_version: 1, base: :web, plugins: [], project: [name: "w", github_org: "acme"], typo: 1}
      """

      assert {:error, [{:unknown_key, [], :typo}]} = Config.read_string(source)
    end
  end

  describe "read_string/1 — schema_version / base / plugins rules" do
    test "rejects an unsupported schema_version" do
      source =
        "%{schema_version: 2, base: :web, plugins: [], project: [name: \"w\", github_org: \"acme\"]}"

      assert {:error, [{:unsupported_schema_version, 2}]} = Config.read_string(source)
    end

    test "rejects an invalid base atom" do
      source =
        "%{schema_version: 1, base: :desktop, plugins: [], project: [name: \"w\", github_org: \"acme\"]}"

      assert {:error, [{:invalid_value, [:base], [:api, :web, :both], :desktop}]} =
               Config.read_string(source)
    end

    test "rejects a non-empty plugins list under schema_version 1" do
      source =
        "%{schema_version: 1, base: :web, plugins: [:extra], project: [name: \"w\", github_org: \"acme\"]}"

      assert {:error, [{:invalid_value, [:plugins], [[]], [:extra]}]} = Config.read_string(source)
    end
  end

  describe "read_string/1 — errors propagate from every section" do
    test "collects a project error alongside a top-level error" do
      source =
        "%{schema_version: 1, base: :web, plugins: [], project: [github_org: \"acme\"], typo: 1}"

      assert {:error, errors} = Config.read_string(source)
      assert {:unknown_key, [], :typo} in errors
      assert {:missing_key, [:project, :name]} in errors
    end

    test "propagates a literal-parser error unchanged" do
      source =
        "%{schema_version: 1, base: :web, plugins: [], project: [name: File.cwd!(), github_org: \"acme\"]}"

      assert {:error, [{:not_literal, [:project, :name], _}]} = Config.read_string(source)
    end

    test "rejects a project section that isn't a keyword list" do
      source = "%{schema_version: 1, base: :web, plugins: [], project: 1}"

      assert Config.read_string(source) ==
               {:error, [{:invalid_type, [:project], "keyword list", 1}]}
    end

    test "rejects a security section that isn't a keyword list, defaulting it" do
      source =
        "%{schema_version: 1, base: :web, plugins: [], project: [name: \"w\", github_org: \"acme\"], security: 1}"

      assert Config.read_string(source) ==
               {:error, [{:invalid_type, [:security], "keyword list", 1}]}
    end
  end

  describe "read/1 and read!/1 — filesystem" do
    test "read/1 reads and validates a real file" do
      config = build(:config)
      path = Path.join(System.tmp_dir!(), "target_#{System.unique_integer([:positive])}.exs")
      File.write!(path, TargetExsFixture.render(config))
      on_exit(fn -> File.rm!(path) end)

      assert Config.read(path) == {:ok, config}
    end

    test "read/1 reports a file_error for a missing path" do
      assert Config.read("/nonexistent/target.exs") == {:error, [{:file_error, :enoent}]}
    end

    test "read!/1 returns the config on success" do
      config = build(:config)
      path = Path.join(System.tmp_dir!(), "target_#{System.unique_integer([:positive])}.exs")
      File.write!(path, TargetExsFixture.render(config))
      on_exit(fn -> File.rm!(path) end)

      assert Config.read!(path) == config
    end

    test "read!/1 raises Capstone.Config.Error naming every problem" do
      assert_raise Capstone.Config.Error, ~r/missing_key.*schema_version/s, fn ->
        Config.read_string!("%{}")
      end
    end
  end
end
