defmodule Capstone.MixExsTest do
  use ExUnit.Case, async: true

  alias Capstone.Factory
  alias Capstone.Source.MixExs

  @patchable [:defp_do, :def_do, :defp_keyword, :inline]

  describe "deps/1" do
    test "reads the declarations from every shape mix accepts" do
      # Deps.declarations/1 read two of these four and returned [] for the
      # others, so a plugin captured from a `def deps do` project recorded
      # no dependencies at all and reported success.
      for shape <- @patchable do
        %{source: source} = Factory.build(:mix_exs_shape, shape: shape)

        assert {:ok, [~s|{:jason, "~> 1.4"}|]} = MixExs.deps(source),
               "shape #{shape} did not read back"
      end
    end

    test "a computed list is located and refused, not silently empty" do
      %{source: source} = Factory.build(:mix_exs_shape, shape: :computed)

      assert MixExs.deps(source) == {:error, {:no_deps_list, :not_a_literal}}
    end

    test "a project with no deps at all is named" do
      %{source: source} = Factory.build(:mix_exs_shape, shape: :no_deps)

      assert MixExs.deps(source) == {:error, {:no_deps_list, :not_found}}
    end

    test "a deps declaration with no body is refused rather than crashing" do
      # `defp deps` alone PARSES, and this module parses rather than compiles,
      # so it must reach the caller as a named error instead of a
      # FunctionClauseError on a clause that does not match.
      %{source: source} = Factory.build(:mix_exs_shape, shape: :bodiless_deps)

      assert MixExs.deps(source) == {:error, {:no_deps_list, :not_a_literal}}
    end

    test "unparseable source is named rather than crashing" do
      assert {:error, {:unparseable, _reason}} = MixExs.deps("defmodule T do\n")
    end
  end

  describe "add_dep/2" do
    test "inserts into every shape, and the result parses" do
      for shape <- @patchable do
        %{source: source} = Factory.build(:mix_exs_shape, shape: shape)

        assert {:ok, patched} = MixExs.add_dep(source, ~s|{:live_svelte, "~> 0.18"}|),
               "shape #{shape} refused"

        assert {:ok, _ast} = Code.string_to_quoted(patched)
        assert {:ok, deps} = MixExs.deps(patched)
        assert ~s|{:live_svelte, "~> 0.18"}| in deps
        assert ~s|{:jason, "~> 1.4"}| in deps
      end
    end

    test "keeps a multi-line list multi-line, and a single-line one single-line" do
      %{source: multi} = Factory.build(:mix_exs_shape, shape: :defp_do)
      %{source: single} = Factory.build(:mix_exs_shape, shape: :defp_keyword)

      {:ok, patched_multi} = MixExs.add_dep(multi, ~s|{:new, "~> 1.0"}|)
      {:ok, patched_single} = MixExs.add_dep(single, ~s|{:new, "~> 1.0"}|)

      assert patched_multi =~ ~s|      {:new, "~> 1.0"},\n      {:jason, "~> 1.4"}|
      assert patched_single =~ ~s|[{:new, "~> 1.0"}, {:jason, "~> 1.4"}]|
    end

    test "adds to an empty list, on one line and across several" do
      # `mix new` writes an EMPTY deps list holding two commented-out examples,
      # so there is no element to patch beside — and replacing the whole list
      # would delete those comments, which are the project's own content.
      one_line =
        "defmodule T.MixProject do\n  def project, do: [app: :t, deps: deps()]\n\n  defp deps, do: []\nend\n"

      multi = File.read!("priv/meta/baseline_otp/mix.exs")

      assert {:ok, patched_one} = MixExs.add_dep(one_line, ~s|{:new, "~> 1.0"}|)
      assert patched_one =~ ~s|do: [{:new, "~> 1.0"}]|

      assert {:ok, patched_multi} = MixExs.add_dep(multi, ~s|{:new, "~> 1.0"}|)
      assert {:ok, _ast} = Code.string_to_quoted(patched_multi)
      assert patched_multi =~ "# {:dep_from_hexpm"
      assert {:ok, [~s|{:new, "~> 1.0"}|]} = MixExs.deps(patched_multi)
    end

    test "is idempotent, decided structurally" do
      # A reflowed declaration must not be mistaken for an absent one and
      # duplicated — mix rejects a duplicate dependency.
      %{source: source} = Factory.build(:mix_exs_shape)

      assert {:ok, ^source} = MixExs.add_dep(source, ~s|{:jason, "~> 1.4"}|)
    end

    test "refuses a computed list rather than guessing" do
      %{source: source} = Factory.build(:mix_exs_shape, shape: :computed)

      assert MixExs.add_dep(source, ~s|{:x, "~> 1.0"}|) ==
               {:error, {:no_deps_list, :not_a_literal}}
    end

    test "leaves every byte outside the deps list untouched" do
      # R6 as an executable claim. The deps list is the only thing that may
      # differ; blank it on both sides and the remainders must be identical.
      %{source: source} = Factory.build(:mix_exs_shape)
      {:ok, patched} = MixExs.add_dep(source, ~s|{:live_svelte, "~> 0.18"}|)

      assert blank_lists(source) == blank_lists(patched)
    end
  end

  describe "project_keys/1 and put_project_key/3" do
    test "reads the project keyword list" do
      %{source: source} = Factory.build(:mix_exs_shape)

      assert {:ok, keys} = MixExs.project_keys(source)
      assert Keyword.has_key?(keys, :app)
      assert Keyword.has_key?(keys, :deps)
    end

    test "adds a key" do
      %{source: source} = Factory.build(:mix_exs_shape)

      assert {:ok, patched} = MixExs.put_project_key(source, :listeners, "[Phoenix.CodeReloader]")
      assert {:ok, _ast} = Code.string_to_quoted(patched)
      assert {:ok, keys} = MixExs.project_keys(patched)
      assert Keyword.has_key?(keys, :listeners)
      assert Keyword.has_key?(keys, :app)
    end

    test "replaces a key that already exists" do
      %{source: source} = Factory.build(:mix_exs_shape)

      assert {:ok, patched} = MixExs.put_project_key(source, :app, ":renamed")
      assert {:ok, keys} = MixExs.project_keys(patched)
      assert keys[:app] == ":renamed"
    end

    test "is idempotent" do
      %{source: source} = Factory.build(:mix_exs_shape)

      assert {:ok, ^source} = MixExs.put_project_key(source, :app, ":t")
    end

    test "a module with no project/0 is named" do
      assert MixExs.project_keys("defmodule T do\nend\n") ==
               {:error, {:no_project_function, :not_found}}

      assert MixExs.put_project_key("defmodule T do\nend\n", :app, ":t") ==
               {:error, {:no_project_function, :not_found}}
    end
  end

  describe "aliases/1 and put_alias/3" do
    test "reads an existing aliases/0" do
      %{source: source} = Factory.build(:mix_exs_shape, shape: :with_aliases)

      assert {:ok, [{:setup, [~s|"deps.get"|]}]} = MixExs.aliases(source)
    end

    test "a project with no aliases/0 is named" do
      %{source: source} = Factory.build(:mix_exs_shape, shape: :without_aliases)

      assert MixExs.aliases(source) == {:error, {:no_aliases, :not_found}}
    end

    test "adds a key to an existing aliases/0" do
      %{source: source} = Factory.build(:mix_exs_shape, shape: :with_aliases)

      assert {:ok, patched} =
               MixExs.put_alias(source, :"assets.build", [~s|"cmd --cd assets pnpm build"|])

      assert {:ok, _ast} = Code.string_to_quoted(patched)
      assert {:ok, aliases} = MixExs.aliases(patched)
      assert aliases[:"assets.build"] == [~s|"cmd --cd assets pnpm build"|]
      assert aliases[:setup] == [~s|"deps.get"|]
    end

    test "replaces the command list of a key that already exists" do
      # The 'replacement at a matched site' shape: the key survives and its
      # value changes. cqrs overwrites setup: and test: exactly this way.
      %{source: source} = Factory.build(:mix_exs_shape, shape: :with_aliases)

      assert {:ok, patched} =
               MixExs.put_alias(source, :setup, [~s|"deps.get"|, ~s|"assets.setup"|])

      assert {:ok, aliases} = MixExs.aliases(patched)
      assert aliases[:setup] == [~s|"deps.get"|, ~s|"assets.setup"|]
    end

    test "creates aliases/0 and wires it into project/0 when absent" do
      # The ordinary case on a `mix new` project, and the one the Svelte layer
      # hits on every install. Without the project/0 wiring the function exists
      # and mix never calls it — inert, and silently so.
      %{source: source} = Factory.build(:mix_exs_shape, shape: :without_aliases)

      assert {:ok, patched} = MixExs.put_alias(source, :setup, [~s|"deps.get"|])
      assert {:ok, _ast} = Code.string_to_quoted(patched)
      assert {:ok, aliases} = MixExs.aliases(patched)
      assert aliases[:setup] == [~s|"deps.get"|]

      assert {:ok, keys} = MixExs.project_keys(patched)
      assert keys[:aliases] == "aliases()"
    end

    test "is idempotent on an unchanged command list" do
      %{source: source} = Factory.build(:mix_exs_shape, shape: :with_aliases)

      assert {:ok, ^source} = MixExs.put_alias(source, :setup, [~s|"deps.get"|])
    end

    test "a module with no project/0 cannot have aliases created" do
      assert MixExs.put_alias("defmodule T do\nend\n", :setup, [~s|"x"|]) ==
               {:error, {:no_project_function, :not_found}}
    end

    test "unparseable source propagates rather than being read as absent aliases" do
      # The branch that matters: an unparseable file must NOT look like "this
      # project has no aliases/0", which would send it down the create path and
      # write into a file that does not parse.
      assert {:error, {:unparseable, _reason}} =
               MixExs.put_alias("defmodule T do\n", :setup, [~s|"x"|])
    end

    test "an alias declared as a bare command reads back as a one-command list" do
      # `defp aliases, do: [setup: "deps.get"]` is accepted by mix, so it must
      # be read rather than refused.
      %{source: source} = Factory.build(:mix_exs_shape, shape: :scalar_alias)

      assert {:ok, [{:setup, [~s|"deps.get"|]}]} = MixExs.aliases(source)
    end

    test "creating aliases/0 works on a module whose body is a single expression" do
      # `mix new`'s mix.exs has more than one function, but a module body that
      # is one expression is not a block, and append_function/4 must still find
      # its last child.
      source = "defmodule T.MixProject do\n  def project, do: [app: :t]\nend\n"

      assert {:ok, patched} = MixExs.put_alias(source, :setup, [~s|"deps.get"|])
      assert {:ok, _ast} = Code.string_to_quoted(patched)
      assert {:ok, [{:setup, [~s|"deps.get"|]}]} = MixExs.aliases(patched)
    end
  end

  describe "a project/0 that is not a literal" do
    test "is located and refused rather than patched" do
      %{source: source} = Factory.build(:mix_exs_shape, shape: :computed_project)

      assert MixExs.project_keys(source) == {:error, {:no_project_function, :not_found}}

      assert MixExs.put_project_key(source, :app, ":t") ==
               {:error, {:no_project_function, :not_found}}
    end
  end

  defp blank_lists(source), do: String.replace(source, ~r/\[[^\]]*\]/s, "[]")
end
