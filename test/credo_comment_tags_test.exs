defmodule CredoCommentTagsTest do
  @moduledoc """
  Asserts the comment-tag vocabulary defined in `.claude/10-comment-tags.md`:
  the `.credo.exs` config, the four tags that block, and the six that do not.

  Without this, zeroing an `exit_status` or dropping a check silently widens
  what can ship — a pending problem becomes a comment nobody has to act on.

  Two halves, and both matter -- but only one of them runs by default. The
  config assertions catch an edit to `.credo.exs`: a check dropped from
  `enabled`, an `exit_status` zeroed, an advisory tag given a check of its
  own. The `measured behaviour` block catches everything those cannot,
  including a custom check that silently stops loading -- credo IGNORES an
  enabled check it cannot resolve and still exits 0, so a renamed or broken
  module in `credo/checks/` disarms `# BUG:`/`# XXX:` without failing
  anything. That block is tagged `:credo_tags`, which `test/test_helper.exs`
  and `.github/workflows/ci.yml` both exclude, so nothing runs it unless
  someone asks:

      mix test --include credo_tags

  Until that changes, the end-to-end proof that the four blocking tags block
  is opt-in, not automatic.
  """

  use ExUnit.Case, async: false

  alias Credo.Check.Design.TagHelper
  alias Credo.SourceFile

  @root Path.expand("..", __DIR__)
  @config Path.join(@root, ".credo.exs")

  # `.claude/10-comment-tags.md`: red, orange and purple block; yellow, amber,
  # blue and gray are advisory.
  @blocking ~w(TODO FIXME BUG XXX)
  @advisory ~w(HACK WARN WARNING NOTE INFO DEPRECATED)

  # Held as strings, not module atoms, on purpose: naming the four modules
  # directly would push this module past the `max_deps: 10` that .credo.exs
  # mandates, and the assertion is about what the config file records anyway.
  @checks %{
    "TODO" => "Credo.Check.Design.TagTODO",
    "FIXME" => "Credo.Check.Design.TagFIXME",
    "BUG" => "Capstone.Check.TagBUG",
    "XXX" => "Capstone.Check.TagXXX"
  }

  # A `.ex` under `test/` is scanned by Credo (its `files.included` carries
  # `test/`) but never compiled by Mix, whose `elixirc_paths` is `lib` only
  # outside `:test` (and `lib`/`test/support` under it). That is what makes it
  # safe to write one mid-suite.
  @probe Path.join(@root, "test/tag_probe.ex")

  setup do
    File.rm(@probe)
    on_exit(fn -> File.rm(@probe) end)
    :ok
  end

  describe ".credo.exs" do
    test "every blocking tag has an enabled check with a non-zero exit_status" do
      enabled = enabled_checks()

      for {tag, module} <- @checks do
        params = Map.get(enabled, module)

        assert params, "#{tag}: #{module} is not in the enabled checks of .credo.exs"

        assert params[:exit_status] == 2,
               "#{tag}: #{module} must keep exit_status 2, got #{inspect(params[:exit_status])}"
      end
    end

    test "no advisory tag has a check of its own" do
      names = Map.keys(enabled_checks())

      for tag <- @advisory do
        refute Enum.any?(names, &(&1 =~ ~r/Tag#{tag}$/i)),
               "#{tag} is advisory and must stay unchecked -- a build that refuses it " <>
                 "teaches people to stop writing it"
      end
    end

    test "requires: resolves to both custom check files" do
      requires = config()[:requires]

      assert requires != [],
             "requires: is empty, so the BUG and XXX checks never load"

      found =
        requires
        |> Enum.flat_map(&Path.wildcard(Path.join(@root, &1)))
        |> Enum.map(&Path.basename/1)
        |> Enum.sort()

      assert found == ["no_runtime_deps.ex", "tag_bug.ex", "tag_xxx.ex"]
    end

    test "the custom checks live outside lib/ so they never ship in the build" do
      for file <- ["tag_bug.ex", "tag_xxx.ex"] do
        assert File.exists?(Path.join(@root, "credo/checks/#{file}"))
      end

      refute File.exists?(Path.join(@root, "lib/tag_bug.ex"))

      beams =
        @root
        |> Path.join("_build/*/lib/*/ebin/*TagBUG.beam")
        |> Path.wildcard()

      assert beams == [],
             "a custom check was compiled into the application: #{inspect(beams)}"
    end

    test "strict mode is on" do
      assert config()[:strict] == true
    end
  end

  describe "measured behaviour" do
    @describetag :credo_tags

    test "a probe with no tag exits 0" do
      assert credo_exit(nil) == 0, "the baseline must be clean or the rest proves nothing"
    end

    test "each blocking tag exits 2" do
      for tag <- @blocking do
        assert credo_exit(tag) == 2, "#{tag} must block the build"
      end
    end

    test "each advisory tag exits 0" do
      for tag <- @advisory do
        assert credo_exit(tag) == 0, "#{tag} is advisory and must not block the build"
      end
    end
  end

  # This one carries no `:credo_tags` tag on purpose: it shells out to
  # nothing. `TagHelper.tags/3` and `SourceFile.parse/2` both run in this
  # process, so it is neither slow nor part of the intermittent failure the
  # tag exists to quarantine, and excluding it alongside the three that do
  # spawn `mix credo` would remove a cheap assertion from every default run
  # and from CI for no reason.
  describe "tag detection" do
    test "is deterministic across repeated calls on the same SourceFile" do
      Application.ensure_all_started(:credo)

      source = """
      defmodule DeterministicTagOrder do
        # TODO: first comment tag

        @moduledoc "TODO: later module doc tag"

        def ok, do: :ok
      end
      """

      source_file = SourceFile.parse(source, "deterministic_tag_order.ex")

      # `TagHelper.tags/3` walks doc-string tags and comment tags in two
      # separate passes and concatenates them -- with `include_doc: true` the
      # doc-string pass runs first, so the result is doc tags before comment
      # tags, not line order (here: line 4 ahead of line 2). That order is
      # stable, so determinism is real and worth asserting; line order is
      # not, so the tags below are compared line-keyed rather than as a
      # sequence. Do not "fix" this back into a line-order assertion.
      tags = TagHelper.tags(source_file, "TODO", true)
      tags_again = TagHelper.tags(source_file, "TODO", true)

      assert tags == tags_again,
             "TagHelper.tags/3 must return identical results across calls on the same SourceFile"

      by_line = Map.new(tags, fn {line_no, _line, trigger} -> {line_no, trigger} end)

      # The comment-tag trigger keeps its leading `#` (the regex match starts
      # there); the doc-attribute trigger is the trimmed doc string itself,
      # with no such prefix.
      assert by_line == %{
               2 => "# TODO: first comment tag",
               4 => "TODO: later module doc tag"
             }
    end
  end

  # --- helpers ----------------------------------------------------------------

  defp config do
    {%{configs: [config | _]}, _bindings} = Code.eval_file(@config)
    config
  end

  # Keyed by the module's printed name so this module does not take a compile
  # dependency on the four checks it asserts about -- see @checks.
  defp enabled_checks do
    config()[:checks][:enabled]
    |> Enum.map(fn
      {module, params} when is_list(params) -> {inspect(module), params}
      {module, _falsey} -> {inspect(module), []}
      module -> {inspect(module), []}
    end)
    |> Map.new()
  end

  defp credo_exit(tag) do
    write_probe(tag)

    {_output, code} =
      System.cmd("mix", ["credo", "--strict"],
        cd: @root,
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "test"}]
      )

    code
  end

  # The probe carries a @moduledoc and a @doc because Credo ORs the exit
  # statuses of every category it reports. A probe that also trips a
  # readability check exits 4, and a blocking tag on top of that exits 6 --
  # which reads as a pass for neither set. The baseline has to be 0.
  defp write_probe(tag) do
    comment = if tag, do: "\n  # #{tag}: planted by CredoCommentTagsTest\n", else: ""

    File.write!(@probe, """
    defmodule TagProbe do
      @moduledoc \"""
      Probe written by CredoCommentTagsTest. Deleted on exit.
      \"""
    #{comment}
      @doc \"""
      Does nothing.
      \"""
      def noop, do: :ok
    end
    """)
  end
end
