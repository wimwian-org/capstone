defmodule Capstone.Plugin.DiffTest do
  use ExUnit.Case, async: true

  alias Capstone.Factory
  alias Capstone.Plugin.Diff

  setup do
    {:ok, Factory.build(:meta_pair)}
  end

  describe "changes/2" do
    test "partitions paths into added, modified and removed", %{baseline: b, meta: m} do
      assert Diff.changes(b, m) == %{
               added: ["lib/app/cache.ex"],
               modified: ["config/config.exs", "lib/app/application.ex", "mix.exs"],
               removed: []
             }
    end

    test "a file present in the baseline but not the meta project is removed", %{
      baseline: b,
      meta: m
    } do
      File.rm!(Path.join(m, "config/config.exs"))

      assert %{removed: ["config/config.exs"]} = Diff.changes(b, m)
    end
  end

  describe "hunks/2" do
    test "returns added lines with indentation preserved", %{baseline: b, meta: m} do
      hunks =
        Diff.hunks(
          Path.join(b, "lib/app/application.ex"),
          Path.join(m, "lib/app/application.ex")
        )

      # Indentation is load-bearing: Classify uses column 0 to tell an appendable
      # block from an insertion inside an existing literal.
      assert [%{lines: ["      App.Repo,", "      App.Cache"]}] = hunks
    end

    test "carries the preceding context so apply can place the hunk", %{baseline: b, meta: m} do
      [hunk] =
        Diff.hunks(
          Path.join(b, "lib/app/application.ex"),
          Path.join(m, "lib/app/application.ex")
        )

      # Three lines, not one: a single preceding line is routinely ambiguous —
      # in cache_component's lib/new_otp_app.ex it is `  """`, which matches twice.
      assert hunk.anchor == [
               "defmodule App.Application do",
               "  def start(_, _) do",
               "    children = ["
             ]
    end

    test "a top-level addition comes back at column 0", %{baseline: b, meta: m} do
      [hunk] = Diff.hunks(Path.join(b, "config/config.exs"), Path.join(m, "config/config.exs"))

      # Myers pairs the added line with the trailing blank that followed it, and
      # puts the significant line FIRST. Classify drops blanks before testing
      # column 0, so hunk ordering cannot change a verdict either way.
      assert hunk.lines == ["config :app, App.Cache, adapter: Nebulex", ""]
    end
  end

  describe "hunks/2 with deletions" do
    test "a replaced line records both halves in one hunk" do
      %{baseline: b, meta: m} = Factory.build(:meta_pair, variety: :rewrite)

      [hunk] = Diff.hunks(Path.join(b, "assets/css/app.css"), Path.join(m, "assets/css/app.css"))

      # ONE hunk, not two: Myers emits {:del, old} immediately followed by
      # {:ins, new} for a replacement, and a human resolving this needs both
      # halves in one place.
      assert hunk.removed == ["@plugin \"daisyui\";"]
      assert hunk.lines == ["@source \"../svelte/**/*.svelte\";"]
    end

    test "the anchor is the text before what was replaced, not before what was added" do
      %{baseline: b, meta: m} = Factory.build(:meta_pair, variety: :rewrite)

      [hunk] = Diff.hunks(Path.join(b, "assets/css/app.css"), Path.join(m, "assets/css/app.css"))

      assert hunk.anchor == ["@import \"tailwindcss\" source(none);", "@source \"../css\";"]
    end

    test "a deletion with no insertion beside it is a hunk of its own" do
      %{baseline: b, meta: m} = Factory.build(:meta_pair, variety: :deleting)

      [hunk] = Diff.hunks(Path.join(b, "config/config.exs"), Path.join(m, "config/config.exs"))

      # The regression: with {:del, _} discarded this returned [], the file
      # classified as :contributes, and apply appended nothing while reporting
      # :ok.
      assert hunk.lines == []
      assert hunk.removed == ["config :myapp, legacy: true"]
    end

    test "a deletion running to the end of the diff is not lost" do
      %{baseline: b, meta: m} = Factory.build(:meta_pair, variety: :deleting)

      # README.md has no trailing newline, so nothing follows the deletion and
      # only the flush after the reduce can emit it.
      [hunk] = Diff.hunks(Path.join(b, "README.md"), Path.join(m, "README.md"))

      assert hunk.lines == []
      assert hunk.removed == ["legacy"]
    end

    test "an insertion with nothing deleted beside it carries an empty removed" do
      %{baseline: b, meta: m} = Factory.build(:meta_pair)

      [hunk] = Diff.hunks(Path.join(b, "config/config.exs"), Path.join(m, "config/config.exs"))

      assert hunk.removed == []
    end

    test "adding to a list literal deletes the line that gains the comma" do
      %{baseline: b, meta: m} = Factory.build(:meta_pair)

      [hunk] =
        Diff.hunks(
          Path.join(b, "lib/app/application.ex"),
          Path.join(m, "lib/app/application.ex")
        )

      # Not an edge case — it is what every insertion into a list literal looks
      # like, and the reason the spec accepts that forcing :manual on any
      # deletion is coarse. `App.Repo` is deleted so `App.Repo,` can replace it.
      assert hunk.removed == ["      App.Repo"]
      assert hunk.lines == ["      App.Repo,", "      App.Cache"]
    end
  end
end
