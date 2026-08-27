defmodule Capstone.ConfigExsTest do
  use ExUnit.Case, async: true

  alias Capstone.Factory
  alias Capstone.Source.ConfigExs

  describe "insert_before_import/2" do
    test "splices above import_config, not after it" do
      # The reproduced defect. Measured on priv/meta/baseline_api: the
      # contribution landed at line 45 with import_config at line 43, so it
      # outranked the project's own dev.exs, test.exs and prod.exs for that
      # key. Phoenix ships a comment three lines above import_config stating
      # exactly the invariant that breaks.
      %{source: source} = Factory.build(:config_shape, shape: :with_import)

      assert {:ok, patched} = ConfigExs.insert_before_import(source, "config :t, added: true\n")

      lines = String.split(patched, "\n")
      import_at = Enum.find_index(lines, &String.starts_with?(&1, "import_config"))
      added_at = Enum.find_index(lines, &String.contains?(&1, "added: true"))

      assert added_at < import_at
    end

    test "appends when there is no import_config to sit above" do
      # Correct here, because nothing follows that the block could override.
      %{source: source} = Factory.build(:config_shape, shape: :without_import)

      assert {:ok, patched} = ConfigExs.insert_before_import(source, "config :t, added: true\n")
      assert String.ends_with?(patched, "config :t, added: true\n")
    end

    test "the result parses and keeps every original statement" do
      %{source: source} = Factory.build(:config_shape, shape: :with_import)
      {:ok, patched} = ConfigExs.insert_before_import(source, "config :t, added: true\n")

      assert {:ok, _ast} = Code.string_to_quoted(patched)
      assert patched =~ "config :t, key: :value"
      assert patched =~ "import_config"
      # The comment that states the invariant must survive the splice.
      assert patched =~ "must remain at the bottom"
    end

    test "is idempotent" do
      %{source: source} = Factory.build(:config_shape, shape: :with_import)
      {:ok, once} = ConfigExs.insert_before_import(source, "config :t, added: true\n")
      {:ok, twice} = ConfigExs.insert_before_import(once, "config :t, added: true\n")

      assert twice == once
    end

    test "splices above a bare import_config that carries no comment" do
      # phx.new always writes the comment, but a project that has edited it
      # away must still get the block above the import rather than below it.
      source = "import Config\n\nconfig :t, key: :value\n\nimport_config \"prod.exs\"\n"

      assert {:ok, patched} = ConfigExs.insert_before_import(source, "config :t, added: true\n")

      lines = String.split(patched, "\n")

      assert Enum.find_index(lines, &String.contains?(&1, "added: true")) <
               Enum.find_index(lines, &String.starts_with?(&1, "import_config"))
    end

    test "unparseable source is named rather than crashing" do
      assert {:error, {:unparseable, _reason}} =
               ConfigExs.insert_before_import("config :t,\n", "x\n")
    end

    test "works against the real baseline, above its import_config (regression)" do
      # The fixture is a reduction; this is the file the defect was measured on.
      source = File.read!("priv/meta/baseline_api/config/config.exs")

      {:ok, patched} =
        ConfigExs.insert_before_import(source, "config :new_api_app, added: true\n")

      lines = String.split(patched, "\n")

      assert Enum.find_index(lines, &String.contains?(&1, "added: true")) <
               Enum.find_index(lines, &String.starts_with?(&1, "import_config"))

      assert {:ok, _ast} = Code.string_to_quoted(patched)
    end
  end

  describe "insert_in_env/3" do
    test "splices inside the guard rather than after it" do
      %{source: source} = Factory.build(:config_shape, shape: :with_env_guard)

      assert {:ok, patched} = ConfigExs.insert_in_env(source, :prod, "config :t, added: true\n")

      lines = String.split(patched, "\n")
      end_at = Enum.find_index(lines, &(&1 == "end"))
      added_at = Enum.find_index(lines, &String.contains?(&1, "added: true"))

      assert added_at < end_at
      assert {:ok, _ast} = Code.string_to_quoted(patched)
    end

    test "a file with no guard errors rather than appending" do
      # Appending is how a production-only secret becomes a test default, so
      # falling back is forbidden here even though it is correct for
      # insert_before_import/2.
      %{source: source} = Factory.build(:config_shape, shape: :without_import)

      assert ConfigExs.insert_in_env(source, :prod, "config :t, secret: 1\n") ==
               {:error, {:no_env_guard, :prod}}
    end

    test "a guard for a different environment is not a match" do
      %{source: source} = Factory.build(:config_shape, shape: :with_env_guard)

      assert ConfigExs.insert_in_env(source, :test, "config :t, x: 1\n") ==
               {:error, {:no_env_guard, :test}}
    end

    test "is idempotent" do
      %{source: source} = Factory.build(:config_shape, shape: :with_env_guard)
      {:ok, once} = ConfigExs.insert_in_env(source, :prod, "config :t, added: true\n")
      {:ok, twice} = ConfigExs.insert_in_env(once, :prod, "config :t, added: true\n")

      assert twice == once
    end

    test "unparseable source is named" do
      assert {:error, {:unparseable, _reason}} =
               ConfigExs.insert_in_env("config :t,\n", :prod, "x\n")
    end

    test "a multi-line block keeps its internal blank lines blank" do
      # The indentation is applied here rather than by Capstone.Vendor.Sourceror, precisely so
      # a blank line inside the block does not acquire trailing whitespace the
      # meta file does not have — which derive's byte-exact replay would
      # reject.
      %{source: source} = Factory.build(:config_shape, shape: :with_env_guard)
      block = "config :t, one: 1\n\nconfig :t, two: 2\n"

      assert {:ok, patched} = ConfigExs.insert_in_env(source, :prod, block)
      assert patched =~ "  config :t, one: 1\n\n  config :t, two: 2"
      refute patched =~ "  \n  config :t, two"
      assert {:ok, _ast} = Code.string_to_quoted(patched)
    end

    test "a block that is entirely whitespace inserts nothing visible" do
      source = "import Config\nif config_env() == :prod do\n  config :t, a: 1\nend\n"

      assert {:ok, patched} = ConfigExs.insert_in_env(source, :prod, "  \n")
      assert {:ok, _ast} = Code.string_to_quoted(patched)
      assert patched =~ "config :t, a: 1"
    end

    test "works against the real runtime.exs, inside its prod guard" do
      source = File.read!("priv/meta/baseline_api/config/runtime.exs")

      {:ok, patched} =
        ConfigExs.insert_in_env(source, :prod, "config :new_api_app, added: true\n")

      assert {:ok, _ast} = Code.string_to_quoted(patched)
      # Inside the guard: the statement must not be reachable outside :prod.
      [_before, inside] = String.split(patched, "if config_env() == :prod do", parts: 2)
      [guarded, _after] = String.split(inside, "\nend\n", parts: 2)
      assert guarded =~ "added: true"
    end
  end

  describe "put_key/4" do
    test "replaces one key and leaves the rest of the statement alone" do
      %{source: source} = Factory.build(:config_shape, shape: :with_repo)

      assert {:ok, patched} = ConfigExs.put_key(source, [:t, T.Repo], :password, ~s|"dba4PG"|)

      assert patched =~ ~s|password: "dba4PG"|
      refute patched =~ ~s|password: "postgres"|
      assert patched =~ ~s|username: "postgres"|
      assert patched =~ ~s|hostname: "localhost"|
      assert {:ok, _ast} = Code.string_to_quoted(patched)
    end

    test "an absent statement errors rather than inserting one" do
      # "override" and "introduce" are different intentions, and conflating
      # them is how a typo becomes a new config key nobody reads.
      %{source: source} = Factory.build(:config_shape, shape: :with_repo)

      assert ConfigExs.put_key(source, [:other, Other.Repo], :password, ~s|"x"|) ==
               {:error, {:no_statement, [:other, Other.Repo]}}
    end

    test "an absent key errors rather than adding one" do
      %{source: source} = Factory.build(:config_shape, shape: :with_repo)

      assert ConfigExs.put_key(source, [:t, T.Repo], :pool_size, "5") ==
               {:error, {:no_key, :pool_size}}
    end

    test "is idempotent" do
      %{source: source} = Factory.build(:config_shape, shape: :with_repo)
      {:ok, once} = ConfigExs.put_key(source, [:t, T.Repo], :password, ~s|"dba4PG"|)
      {:ok, twice} = ConfigExs.put_key(once, [:t, T.Repo], :password, ~s|"dba4PG"|)

      assert twice == once
    end

    test "a two-element path addresses a bare `config :app, key: value`" do
      %{source: source} = Factory.build(:config_shape, shape: :without_import)

      assert {:ok, patched} = ConfigExs.put_key(source, [:t], :key, ":replaced")
      assert patched =~ "key: :replaced"
      refute patched =~ "key: :value"
    end

    test "a statement whose settings are not a keyword list has no key to replace" do
      # `config :phoenix, :json_library, Jason` is real — it is in every
      # phx.new config.exs — and addresses one setting rather than a block of
      # them, so there is nothing named `key` inside it.
      source = "import Config\n\nconfig :phoenix, :json_library, Jason\n"

      assert ConfigExs.put_key(source, [:phoenix, :json_library], :key, "1") ==
               {:error, {:no_key, :key}}
    end

    test "a statement addressed by a computed argument is not matched" do
      # The leading argument is a call, not a literal or an alias. It cannot
      # equal an atom in the path, and reaching for one must not crash.
      source = "import Config\n\nconfig otp_app(), key: :value\n"

      assert ConfigExs.put_key(source, [:t], :key, ":replaced") ==
               {:error, {:no_statement, [:t]}}
    end

    test "unparseable source is named" do
      assert {:error, {:unparseable, _reason}} =
               ConfigExs.put_key("config :t,\n", [:t], :key, "1")
    end

    test "leaves every byte outside the replaced value untouched" do
      %{source: source} = Factory.build(:config_shape, shape: :with_repo)
      {:ok, patched} = ConfigExs.put_key(source, [:t, T.Repo], :password, ~s|"dba4PG"|)

      # Every line but the one holding the replaced value must be identical —
      # `username:` also says "postgres", so a global replace would compare the
      # wrong thing.
      drop_password = fn text ->
        text |> String.split("\n") |> Enum.reject(&String.contains?(&1, "password:"))
      end

      assert drop_password.(source) == drop_password.(patched)
      assert patched =~ ~s|  password: "dba4PG",|
    end
  end
end
