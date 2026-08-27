defmodule Capstone.Config.ProjectTest do
  use ExUnit.Case, async: true

  alias Capstone.Config.Project

  describe "from_keyword/2 — valid input" do
    test "builds a struct with all four fields given" do
      fields = [name: "widgets", module: Widgets, app: :widgets, github_org: "acme"]

      assert Project.from_keyword(fields, [:project]) ==
               {:ok,
                %Project{name: "widgets", module: Widgets, app: :widgets, github_org: "acme"}}
    end

    test "derives module and app from name when absent" do
      fields = [name: "my_widgets", github_org: "acme"]

      assert Project.from_keyword(fields, [:project]) ==
               {:ok,
                %Project{
                  name: "my_widgets",
                  module: MyWidgets,
                  app: :my_widgets,
                  github_org: "acme"
                }}
    end
  end

  describe "from_keyword/2 — required fields" do
    test "reports missing name and github_org" do
      assert {:error, errors} = Project.from_keyword([], [:project])
      assert {:missing_key, [:project, :name]} in errors
      assert {:missing_key, [:project, :github_org]} in errors
    end
  end

  describe "from_keyword/2 — type errors" do
    test "reports a non-string name" do
      fields = [name: :not_a_string, github_org: "acme"]

      assert {:error, [{:invalid_type, [:project, :name], _, :not_a_string}]} =
               Project.from_keyword(fields, [:project])
    end

    test "reports an empty-string github_org" do
      fields = [name: "widgets", github_org: ""]

      assert {:error, [{:invalid_type, [:project, :github_org], _, ""}]} =
               Project.from_keyword(fields, [:project])
    end

    test "reports a non-atom module" do
      fields = [name: "widgets", module: "Widgets", github_org: "acme"]

      assert {:error, [{:invalid_type, [:project, :module], "module()", "Widgets"}]} =
               Project.from_keyword(fields, [:project])
    end

    test "reports a non-atom app with an atom()-specific description" do
      fields = [name: "widgets", app: "widgets", github_org: "acme"]

      assert {:error, [{:invalid_type, [:project, :app], "atom()", "widgets"}]} =
               Project.from_keyword(fields, [:project])
    end

    test "rejects a name containing a hyphen" do
      fields = [name: "my-app", github_org: "acme"]

      assert {:error, [{:invalid_type, [:project, :name], _, "my-app"}]} =
               Project.from_keyword(fields, [:project])
    end

    test "rejects a name starting with an uppercase letter" do
      fields = [name: "MyApp", github_org: "acme"]

      assert {:error, [{:invalid_type, [:project, :name], _, "MyApp"}]} =
               Project.from_keyword(fields, [:project])
    end

    test "rejects a name starting with a digit" do
      fields = [name: "1app", github_org: "acme"]

      assert {:error, [{:invalid_type, [:project, :name], _, "1app"}]} =
               Project.from_keyword(fields, [:project])
    end

    test "accepts a valid lowercase-underscore name and derives module/app from it" do
      fields = [name: "my_app", github_org: "acme"]

      assert Project.from_keyword(fields, [:project]) ==
               {:ok, %Project{name: "my_app", module: MyApp, app: :my_app, github_org: "acme"}}
    end
  end

  describe "from_keyword/2 — unknown keys" do
    test "reports a key not in the schema" do
      fields = [name: "widgets", github_org: "acme", typo_field: 1]

      assert {:error, [{:unknown_key, [:project], :typo_field}]} =
               Project.from_keyword(fields, [:project])
    end
  end
end
