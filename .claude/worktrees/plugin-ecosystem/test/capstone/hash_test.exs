defmodule Capstone.HashTest do
  use ExUnit.Case, async: true

  alias Capstone.Factory
  alias Capstone.Hash

  # U+FEFF spelled as its UTF-8 bytes, not as the invisible character itself:
  # an editor or a copy-paste silently dropping the literal would leave a test
  # that passes without ever exercising the strip.
  @bom <<0xEF, 0xBB, 0xBF>>

  test "adding a comment to an .ex or an .exs file does not change its hash" do
    # THE requirement the whole design exists for: a
    # `# credo:disable-for-next-line` must never lock a project out of updates.
    %{source: source} = Factory.build(:elixir_source)
    commented = "# credo:disable-for-next-line\n" <> source

    assert Hash.content_hash(commented, "a.ex") == Hash.content_hash(source, "a.ex")
    # .exs is not a marginal second case: it is mix.exs, config/config.exs,
    # .formatter.exs and test_helper.exs. Dropped from @elixir_extensions they
    # would silently become comment-SENSITIVE, and only a path ending in .exs
    # can see it.
    assert Hash.content_hash(commented, "a.exs") == Hash.content_hash(source, "a.exs")
  end

  test "reindenting an .ex file does not change its hash" do
    %{source: source} = Factory.build(:elixir_source)
    reindented = String.replace(source, "  ", "      ")
    assert Hash.content_hash(reindented, "a.ex") == Hash.content_hash(source, "a.ex")
  end

  test "reindenting a multi-line sigil DOES change an .ex hash" do
    # The other edge of "reindentation-proof", asserted so it is a decision not
    # an accident: a sigil keeps its interior verbatim in the AST, so widening
    # it is a content change. This is the shape phx.new emits in config.exs,
    # and the .ex fixture avoids it only because it carries no such literal.
    source = "args = ~w(\n  --input=a.css\n  --output=b.css\n)\n"
    reindented = String.replace(source, "  ", "      ")
    refute Hash.content_hash(reindented, "a.ex") == Hash.content_hash(source, "a.ex")
  end

  test "CRLF and a leading BOM do not change an .ex hash" do
    %{source: source} = Factory.build(:elixir_source)
    expected = Hash.content_hash(source, "a.ex")

    assert Hash.content_hash(String.replace(source, "\n", "\r\n"), "a.ex") == expected
    # The parser raises SyntaxError on U+FEFF without an explicit strip. Asserting
    # that first is what keeps the line below from passing on a lost BOM.
    assert_raise SyntaxError, fn -> Code.string_to_quoted!(@bom <> source) end
    assert Hash.content_hash(@bom <> source, "a.ex") == expected
  end

  test "real code changes DO change the hash" do
    %{source: source} = Factory.build(:elixir_source)
    base = Hash.content_hash(source, "a.ex")

    for variety <- [
          :renamed_variable,
          :added_function,
          :changed_literal,
          :changed_atom,
          :changed_moduledoc
        ] do
      %{source: changed} = Factory.build(:elixir_source, variety: variety)
      refute Hash.content_hash(changed, "a.ex") == base
    end
  end

  test "the same bytes hash differently as .ex and as .yaml" do
    # Dispatch is by EXTENSION, never try-parse-then-fall-back: under a
    # fallback scheme the same bytes hash differently depending on whether they
    # happen to be valid Elixir, so introducing a syntax error would silently
    # flip a file's hashing mode and could mask a divergence.
    refute Hash.content_hash("a: 1\n", "x.yaml") == Hash.content_hash("%{a: 1}\n", "x.ex")
  end

  test "a .yaml hash ignores CRLF, trailing whitespace and a BOM but NOT a comment" do
    # Asserts the documented MVP limitation, so it is a decision not an accident.
    base = Hash.content_hash("a: 1\nb: 2\n", "c.yaml")
    assert Hash.content_hash("a: 1  \r\nb: 2\r\n\n", "c.yaml") == base
    refute Hash.content_hash("# added by user\na: 1\nb: 2\n", "c.yaml") == base
    # Pins the BOM strip AHEAD of the extension dispatch: moved inside the
    # Elixir clause, every other test stays green while a BOM-prefixed .yaml
    # starts hashing differently from the same file without one.
    assert Hash.content_hash(@bom <> "a: 1\nb: 2\n", "c.yaml") == base
  end

  test "each parser exception propagates naming the supplied path" do
    # THREE distinct structs — `rescue e in SyntaxError` alone misses the two
    # commonest real-world cases.
    for {variety, exception} <- [
          {:token_missing, TokenMissingError},
          {:mismatched_delimiter, MismatchedDelimiterError},
          {:syntax_error, SyntaxError}
        ] do
      %{source: source} = Factory.build(:unparseable_source, variety: variety)
      assert_raise exception, ~r/given\.ex/, fn -> Hash.content_hash(source, "given.ex") end
    end
  end

  test "hashing legacy code emits nothing on stderr" do
    # emit_warnings: false is mandatory, or a 200-file walk spams the terminal
    # for quoted atoms and single-quoted charlists.
    %{source: source} = Factory.build(:elixir_source, variety: :legacy_charlist)
    assert ExUnit.CaptureIO.capture_io(:stderr, fn -> Hash.content_hash(source, "a.ex") end) == ""
  end

  test "hashes a router.ex referencing an unavailable module" do
    # Parsing is independent of compilation — the step-4 prerequisite.
    source = "defmodule R do\n  use Phoenix.Router\nend\n"
    assert Hash.content_hash(source, "router.ex") =~ ~r/\Asha256:[0-9a-f]{64}\z/
  end

  test "an empty .ex and a comments-only .ex share a hash" do
    # A known collision, asserted explicitly. Both normalise to "".
    assert Hash.content_hash("", "a.ex") == Hash.content_hash("# just a note\n", "a.ex")
  end

  test "normalise/2 preserves source order of a 39-key map literal" do
    %{source: source} = Factory.build(:elixir_source, variety: :wide_map_literal)
    keys = fn text -> ~r/key_\d+/ |> Regex.scan(text) |> List.flatten() end

    assert [one] = 1..5 |> Enum.map(fn _ -> Hash.normalise(source, "a.ex") end) |> Enum.uniq()
    # Repeat-stability alone would pass on any order fixed within one VM. 39
    # keys is past the 32 at which a real map stops preserving insertion order,
    # so equality with the SOURCE order is what says no map was built.
    assert keys.(one) == keys.(source)
  end

  test "hashing every .ex under priv/meta is stable and comment-insensitive" do
    # A real ~40-file offline determinism corpus, courtesy of task 5.
    files = Path.wildcard("priv/meta/**/*.{ex,exs}")
    assert length(files) > 10

    hash_all = fn prefix ->
      Map.new(files, &{&1, Hash.content_hash(prefix <> File.read!(&1), &1)})
    end

    assert hash_all.("") == hash_all.("")
    # Comment-insensitivity proven over the shipped generator output — real
    # moduledocs, heredocs, sigils and `use` calls — not only over one 8-line
    # fixture. Every file in the corpus is .ex or .exs, so every one goes
    # through the parser branch.
    assert hash_all.("# credo:disable-for-next-line\n") == hash_all.("")
  end

  test "content_hash/2 returns sha256: followed by 64 lowercase hex characters" do
    assert Hash.content_hash("x = 1\n", "a.ex") =~ ~r/\Asha256:[0-9a-f]{64}\z/
  end

  test "re-normalising a known non-idempotent source changes the hash" do
    # Encodes the trap in a test. Macro.to_string/1 is NOT idempotent — so the
    # hash must always be taken from the bytes on disk in exactly ONE pass.
    # Never store sha256 of an already-normalised string.
    #
    # The witness is a comprehension whose `do:` precedes `into:`, the shape
    # `String.grapheme_to_binary/1` uses: it prints `into` as a bare line inside
    # the block, which re-parses as a third body expression and re-indents. With
    # `into:` first the printer round-trips, so the pair order is the whole test.
    source = "for x <- [1], do: {x, x}, into: %{}\n"
    once = Hash.normalise(source, "a.ex")
    refute Hash.content_hash(once, "a.ex") == Hash.content_hash(source, "a.ex")
  end

  test "text_hash/1 hashes an .ex that does not parse, as TEXT" do
    # The recorder's case: apply writes a conflict region into a file it has
    # just written, and content_hash/2 raises on it. This is NOT a fallback
    # inside content_hash/2 — the call site chooses, on a fact it already knows.
    # Assembled rather than written whole so this file does not itself contain a
    # marker for `mix capstone.check` to find.
    marked = "defmodule App do\nend\n" <> String.duplicate("<", 7) <> " capstone: k\n"

    assert_raise SyntaxError, fn -> Hash.content_hash(marked, "a.ex") end
    assert Hash.text_hash(marked) =~ ~r/\Asha256:[0-9a-f]{64}\z/
    # Byte-identical to what the same content hashes to under a non-Elixir
    # extension, which is what "as TEXT" means.
    assert Hash.text_hash(marked) == Hash.content_hash(marked, "a.txt")
  end

  test "text_hash/1 ignores CRLF, trailing whitespace and a BOM" do
    # The same normalisation the non-Elixir branch applies, asserted directly:
    # text_hash/1 shares that code rather than reimplementing it.
    base = Hash.text_hash("a: 1\nb: 2\n")

    assert Hash.text_hash("a: 1  \r\nb: 2\r\n\n") == base
    assert Hash.text_hash(@bom <> "a: 1\nb: 2\n") == base
    refute Hash.text_hash("# added by user\na: 1\nb: 2\n") == base
  end
end
