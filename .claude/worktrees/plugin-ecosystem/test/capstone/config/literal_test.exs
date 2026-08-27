defmodule Capstone.Config.LiteralTest do
  use ExUnit.Case, async: true

  alias Capstone.Config.Literal

  describe "from_source/1 — accepted literal shapes" do
    test "parses a map with atom keys" do
      assert Literal.from_source("%{a: 1, b: :two}") == {:ok, %{a: 1, b: :two}}
    end

    test "parses nested maps and keyword lists" do
      source = "%{project: [name: \"widgets\", nested: [deep: true]]}"

      assert Literal.from_source(source) ==
               {:ok, %{project: [name: "widgets", nested: [deep: true]]}}
    end

    test "parses a bare module alias as a module literal" do
      assert Literal.from_source("%{module: MyApp}") == {:ok, %{module: MyApp}}
    end

    test "parses a dotted module alias" do
      assert Literal.from_source("%{module: My.App}") == {:ok, %{module: My.App}}
    end

    test "parses booleans and nil as atoms" do
      assert Literal.from_source("%{a: true, b: false, c: nil}") ==
               {:ok, %{a: true, b: false, c: nil}}
    end

    test "parses an empty list" do
      assert Literal.from_source("%{plugins: []}") == {:ok, %{plugins: []}}
    end

    test "parses a plain (non-keyword) list of strings" do
      assert Literal.from_source(~s(["a", "b"])) == {:ok, ["a", "b"]}
    end
  end

  describe "from_source/1 — syntax errors" do
    test "reports a syntax error with a line number" do
      assert {:error, {:syntax_error, 1, description}} = Literal.from_source("%{a: }")
      assert is_binary(description)
    end

    test "reports a syntax error whose description is a {prefix, suffix} tuple" do
      assert {:error, {_location, {"unexpected reserved word: ", ""}, "end"}} =
               Code.string_to_quoted("%{a: 1} end")

      assert {:error, {:syntax_error, 1, description}} = Literal.from_source("%{a: 1} end")
      assert description == "unexpected reserved word: end"
    end
  end

  describe "from_source/1 — rejected non-literal shapes" do
    test "rejects a function call, at the offending path" do
      assert {:error, {:not_literal, [:project, :name], _quoted}} =
               Literal.from_source("%{project: [name: File.cwd!()]}")
    end

    test "rejects a bare variable reference" do
      source = "x = 1\n%{a: x}"
      assert {:error, {:not_literal, [], _}} = Literal.from_source(source)
    end

    test "rejects string interpolation" do
      assert {:error, {:not_literal, [:a], _}} = Literal.from_source(~s[%{a: "\#{1 + 1}"}])
    end

    test "rejects an operator expression" do
      assert {:error, {:not_literal, [:a], _}} = Literal.from_source("%{a: 1 + 1}")
    end

    test "rejects a sigil" do
      assert {:error, {:not_literal, [:a], _}} = Literal.from_source("%{a: ~r/x/}")
    end

    test "never evaluates a side effect" do
      source = "%{a: send(self(), :evaluated)}"
      Literal.from_source(source)
      refute_received :evaluated
    end

    test "rejects map-update syntax instead of crashing" do
      assert {:error, {:not_literal, [], _}} = Literal.from_source("%{x | a: 1}")
    end

    test "rejects a map with a non-atom key" do
      assert {:error, {:not_literal, [], 1}} = Literal.from_source("%{1 => 2}")
    end

    test "rejects a duplicate key in a map" do
      assert Literal.from_source("%{a: 1, a: 2}") == {:error, {:duplicate_key, [], :a}}
    end

    test "rejects a duplicate key in a keyword-shaped list" do
      assert Literal.from_source("[a: 1, a: 2]") == {:error, {:duplicate_key, [], :a}}
    end

    test "rejects a duplicate key nested inside a section, with the section's path" do
      assert Literal.from_source(~s(%{project: [name: "a", name: "b"]})) ==
               {:error, {:duplicate_key, [:project], :name}}
    end
  end
end
