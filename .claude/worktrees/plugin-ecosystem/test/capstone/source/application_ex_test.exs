defmodule Capstone.ApplicationExTest do
  use ExUnit.Case, async: true

  alias Capstone.Factory
  alias Capstone.Source.ApplicationEx

  describe "children/1" do
    test "reads the supervision children" do
      %{source: source} = Factory.build(:application_shape)

      assert {:ok, ["T.Repo", "TWeb.Endpoint"]} = ApplicationEx.children(source)
    end

    test "an empty list reads as empty rather than erroring" do
      %{source: source} = Factory.build(:application_shape, shape: :empty)

      assert {:ok, []} = ApplicationEx.children(source)
    end

    test "a computed list is refused by name" do
      %{source: source} = Factory.build(:application_shape, shape: :computed)

      assert ApplicationEx.children(source) == {:error, {:children_not_a_literal, :start}}
    end

    test "a module with no start/2 is named" do
      %{source: source} = Factory.build(:application_shape, shape: :no_start)

      assert ApplicationEx.children(source) == {:error, {:no_start_function, :not_found}}
    end

    test "a differently named binding is refused rather than guessed at" do
      # Matching any list inside start/2 would place a child into whichever
      # literal came first, which is exactly the guessing this avoids.
      %{source: source} = Factory.build(:application_shape, shape: :renamed)

      assert ApplicationEx.children(source) == {:error, {:children_not_a_literal, :start}}
    end

    test "unparseable source is named rather than crashing" do
      assert {:error, {:unparseable, _reason}} = ApplicationEx.children("defmodule T do\n")
    end

    test "reads the real baseline's children, comments and all" do
      source = File.read!("priv/meta/baseline_api/lib/new_api_app/application.ex")

      assert {:ok, children} = ApplicationEx.children(source)
      assert "NewApiAppWeb.Telemetry" in children
      assert "NewApiAppWeb.Endpoint" in children
      # The commented-out worker example is a comment, not a child.
      refute Enum.any?(children, &(&1 =~ "Worker"))
    end
  end

  describe "add_child/2" do
    test "appends the child last and keeps the existing ones" do
      # Last, deliberately. A plugin knows its own process needs the repo
      # started first; it cannot know whether it should precede another
      # plugin's, so the only defensible position is after everything the
      # project already had.
      %{source: source} = Factory.build(:application_shape)

      assert {:ok, patched} = ApplicationEx.add_child(source, "T.Cache")
      assert {:ok, ["T.Repo", "TWeb.Endpoint", "T.Cache"]} = ApplicationEx.children(patched)
      assert {:ok, _ast} = Code.string_to_quoted(patched)
    end

    test "accepts a tuple child" do
      %{source: source} = Factory.build(:application_shape)

      assert {:ok, patched} =
               ApplicationEx.add_child(source, "{Oban, Application.fetch_env!(:t, Oban)}")

      assert {:ok, children} = ApplicationEx.children(patched)
      assert "{Oban, Application.fetch_env!(:t, Oban)}" in children
    end

    test "adds to an empty children list" do
      %{source: source} = Factory.build(:application_shape, shape: :empty)

      assert {:ok, patched} = ApplicationEx.add_child(source, "T.Cache")
      assert {:ok, ["T.Cache"]} = ApplicationEx.children(patched)
      assert {:ok, _ast} = Code.string_to_quoted(patched)
    end

    test "is idempotent, decided structurally" do
      # A reflowed entry is not an absent one, and two identical children in a
      # supervision tree is a name clash at boot.
      %{source: source} = Factory.build(:application_shape)

      assert {:ok, ^source} = ApplicationEx.add_child(source, "T.Repo")
    end

    test "refuses a computed list rather than guessing" do
      %{source: source} = Factory.build(:application_shape, shape: :computed)

      assert ApplicationEx.add_child(source, "T.Cache") ==
               {:error, {:children_not_a_literal, :start}}
    end

    test "leaves every byte outside the children list untouched" do
      %{source: source} = Factory.build(:application_shape)
      {:ok, patched} = ApplicationEx.add_child(source, "T.Cache")

      assert blank_children(source) == blank_children(patched)
    end

    test "keeps the real baseline's comments when appending" do
      # The list carries two commented-out examples. Replacing the whole list
      # would delete them, and they are the project's own content.
      source = File.read!("priv/meta/baseline_api/lib/new_api_app/application.ex")

      {:ok, patched} = ApplicationEx.add_child(source, "NewApiApp.Cache")

      assert patched =~ "# Start a worker by calling"
      assert patched =~ "# {NewApiApp.Worker, arg}"
      assert {:ok, _ast} = Code.string_to_quoted(patched)
      assert {:ok, children} = ApplicationEx.children(patched)
      assert List.last(children) == "NewApiApp.Cache"
    end
  end

  defp blank_children(source),
    do: String.replace(source, ~r/children = \[.*?\]/s, "children = []")
end
