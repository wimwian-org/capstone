defmodule Capstone.SourceTest do
  use ExUnit.Case, async: true

  alias Capstone.Factory
  alias Capstone.Source

  test "decode!(encode!(t)) == t for a full fireside-shaped term" do
    term = Factory.build(:fireside_manifest)

    assert Source.decode!(Source.encode!(term), "plugin.exs") == term
  end

  test "encode!(decode!(bytes)) is byte-identical to bytes" do
    bytes = Source.encode!(Factory.build(:exs_term, shape: :two_keys))

    assert Source.encode!(Source.decode!(bytes, "x.exs")) == bytes
  end

  test "decode!/2 raises on an empty file and on a comments-only file" do
    for shape <- [:empty, :comment_only] do
      %{source: source} = Factory.build(:exs_source, shape: shape)

      assert_raise Source.DecodeError, ~r/empty or contains only comments/, fn ->
        Source.decode!(source, "x.exs")
      end
    end
  end

  test "decode!/2 raises naming the expression count for two top-level maps" do
    %{source: source} = Factory.build(:exs_source, shape: :two_maps)

    assert_raise Source.DecodeError, ~r/expected exactly one expression, got 2/, fn ->
      Source.decode!(source, "x.exs")
    end
  end

  test "decode!/2 raises for a keyword list, a bare string and nil at the root" do
    for shape <- [:keyword_list, :bare_string, :nil_root] do
      %{source: source} = Factory.build(:exs_source, shape: shape)

      assert_raise Source.DecodeError, ~r/expected a map at the root/, fn ->
        Source.decode!(source, "x.exs")
      end
    end
  end

  test "decode!/2 raises for an interpolated string and a unary minus" do
    for shape <- [:interpolated_string, :unary_minus] do
      %{source: source} = Factory.build(:exs_source, shape: shape)

      assert_raise Source.DecodeError, ~r/not a literal/, fn ->
        Source.decode!(source, "x.exs")
      end
    end
  end

  test "decode!/2 rejects the single expression inside a one-expression block" do
    # `unquote_splicing/1` is the one top-level form the parser wraps in a
    # __block__ of length 1; every other single expression arrives bare. It is
    # what makes the unwrap-one clause reachable, and an AST-injection attempt
    # in its own right.
    %{source: source} = Factory.build(:exs_source, shape: :unquote_splicing)

    assert_raise Source.DecodeError, ~r/not a literal: unquote_splicing/, fn ->
      Source.decode!(source, "x.exs")
    end
  end

  test "decode!/2 resolves a module alias to a module atom" do
    # target.exs REQUIRES this clause; plugin.exs never exercises it.
    %{source: source} = Factory.build(:exs_source, shape: :module_alias)

    assert Source.decode!(source, "target.exs") == %{module: MyApp}
  end

  test "decode!/2 executes no code and defines no module" do
    %{canary: canary, module: module, source: source} =
      Factory.build(:code_executing_exs_source)

    on_exit(fn -> File.rm_rf!(canary) end)

    assert_raise Source.DecodeError, fn -> Source.decode!(source, "plugin.exs") end
    refute File.exists?(canary)
    refute Code.ensure_loaded?(module)
  end

  test "decode!/2 lets each parser exception propagate carrying the path" do
    cases = [
      {:unclosed_delimiter, TokenMissingError},
      {:mismatched_delimiter, MismatchedDelimiterError},
      {:stray_delimiter, SyntaxError}
    ]

    for {shape, exception} <- cases do
      %{source: source} = Factory.build(:exs_source, shape: shape)

      assert_raise exception, ~r/given\.exs/, fn -> Source.decode!(source, "given.exs") end
    end
  end

  test "encode!/1 sorts map keys at every nesting level" do
    bytes = Source.encode!(Factory.build(:exs_term, shape: :nested_unsorted))

    # Both levels are asserted as ORDERINGS. A presence-only check on the outer
    # key would be satisfied by an encoder that sorted nested maps and left the
    # top level in atom-creation order — which is the exact bug sort_maps exists
    # to prevent.
    assert :binary.match(bytes, "a: 3") < :binary.match(bytes, "z:")
    assert :binary.match(bytes, "a: 2") < :binary.match(bytes, "y: 1")
  end

  test "encode!/1 wraps at the encoder's 80 columns, not at the formatter's 98" do
    # Defends `pretty: true` AND `width: 80`, which nothing else can: the
    # fixed-point test is structurally incapable of it, because
    # `Code.format_string!/1` is idempotent and so re-formats ANY width setting
    # into its own fixed point. Measured — with `pretty` dropped, `inspect/2`
    # passes `:infinity` to the algebra formatter and `width` becomes dead
    # config; with `width: 120` the 84-column term clears 98 untouched. Both
    # mutations leave this term on ONE line, and only this assertion notices.
    bytes = Source.encode!(Factory.build(:exs_term, shape: :eighty_one_to_ninety_eight_columns))

    assert length(String.split(bytes, "\n")) > 2
  end

  test "encode!/1 preserves list and keyword-list order" do
    # sort_maps sorts MAPS only. Plugin and file ordering is Manifest's job.
    bytes = Source.encode!(Factory.build(:exs_term, shape: :ordered_list))

    assert bytes =~ "[:z, :a, :m]"
    assert bytes =~ "[z: 1, a: 2]"
  end

  test "encode!/1 output is a fixed point of Code.format_string! and ends with one newline" do
    bytes = Source.encode!(Factory.build(:exs_term, shape: :long_path))

    assert bytes == IO.iodata_to_binary(Code.format_string!(bytes)) <> "\n"
    refute String.ends_with?(bytes, "\n\n")
  end

  test "encode!/1 raises for a pid, reference, function, struct and MapSet" do
    %{terms: terms} = Factory.build(:unencodable_exs_terms)

    for term <- terms do
      assert_raise Source.EncodeError, fn -> Source.encode!(term) end
    end
  end

  test "encode!/1 round-trips a 250-element list and a 5000-character string" do
    term = Factory.build(:exs_term, shape: :bulky)

    assert Source.decode!(Source.encode!(term), "x.exs") == term
  end

  @tag :determinism
  test "encode!/1 is byte-identical across two processes with reversed atom order" do
    probe = "test/support/determinism_probe.exs"
    ebin = Path.join(Mix.Project.build_path(), "lib/capstone/ebin")

    # The exit status and the digest SHAPE are both asserted before the two
    # runs are compared. Measured: with a bad -pa the probe dies with an
    # UndefinedFunctionError on stderr, System.cmd/3 does not raise, and both
    # directions return "" — so a status-blind `assert fwd == rev` passes while
    # proving nothing. That is the F4 signature, in the one test that carries
    # the codec's central guarantee.
    run = fn dir ->
      {output, status} =
        System.cmd("elixir", ["-pa", ebin, probe, dir], stderr_to_stdout: true)

      trimmed = String.trim(output)

      assert status == 0, "probe #{dir} exited #{status}:\n#{output}"
      assert trimmed =~ ~r/\A[0-9a-f]{64}\z/, "probe #{dir} printed no digest:\n#{output}"

      trimmed
    end

    assert run.("fwd") == run.("rev")
  end
end
