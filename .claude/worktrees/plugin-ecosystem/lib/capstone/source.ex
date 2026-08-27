defmodule Capstone.Source do
  @moduledoc """
  Codec for the plain-data `.exs` files Capstone owns — `target.exs` and
  `plugin.exs`.

  Decoding walks the AST and accepts literals only. There is no evaluation
  step at all, so a manifest cannot execute code, define a module, or silently
  evaluate to `nil`. Code execution here is not defended against — it is
  absent.

  Evaluating the file instead was measured and rejected: an empty file and a
  comment-only file both silently return `nil`, a keyword list and a bare
  string are returned as-is, and a file holding two top-level maps silently
  returns only the last one.

  The prose above deliberately names no evaluating function:
  `Capstone.BoundaryGuard` substring-scans this file, docs and comments
  included, so spelling the rejected API out would make `lib/` fail its own
  boundary test.
  """

  # Every option is load-bearing.
  #   pretty: true      — REQUIRED, and required FIRST: `inspect/2` passes
  #                       `opts.width` to the algebra formatter only when
  #                       `pretty` is true, and `:infinity` otherwise. Without
  #                       it `width: 80` is dead config — measured, width 80 and
  #                       width 120 render byte-identical single-line output —
  #                       and the fixed-point guarantee below would rest on
  #                       nothing but `Code.format_string!/1`'s own idempotence.
  #   sort_maps         — map order follows atom-table CREATION order; it bites
  #                       at 4 keys, not 32, and differs between VMs.
  #   limit/printable   — 1.20 defaults 200 / 4096 emit `...`, which fails to
  #                       re-parse with the baffling `undefined function .../0`.
  #   width: 80         — pinned explicitly, and MUST stay <= the formatter's
  #                       line_length of 98, or format_string! stops being a
  #                       fixed point (the formatter never rejoins a split
  #                       container, so 80-then-98 converges; 120-then-98 does not).
  #   charlists         — `inspect([104, 105])` renders `~c"hi"` otherwise.
  @inspect_opts [
    pretty: true,
    width: 80,
    limit: :infinity,
    printable_limit: :infinity,
    charlists: :as_lists,
    custom_options: [sort_maps: true]
  ]

  @doc """
  Decodes plain-data `.exs` source into a map.

  `path` is used for error messages only. Parser exceptions
  (`SyntaxError`, `TokenMissingError`, `MismatchedDelimiterError`) propagate
  unwrapped — their rendered messages already carry file, line, column and a
  source snippet, which is better than anything we would write.
  """
  @spec decode!(binary(), Path.t()) :: map()
  def decode!(source, path) do
    source
    |> Code.string_to_quoted!(file: path, emit_warnings: false)
    |> unwrap!(path)
    |> literal!(path)
    |> ensure_map!(path)
  end

  @doc """
  Encodes a plain-data map to deterministic `.exs` bytes.

  Raises `Capstone.Source.EncodeError` for anything that is not
  atom/number/binary/list/tuple/plain-map. That check is mandatory, not
  defensive: `inspect` renders a pid, reference, port or struct as `#Foo<...>`,
  and `#` starts an Elixir comment — so the value would round-trip to `nil`
  with no exception anywhere.
  """
  @spec encode!(map()) :: binary()
  def encode!(term) when is_map(term) do
    encodable!(term)

    term
    |> inspect(@inspect_opts)
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  defp unwrap!({:__block__, _meta, []}, path) do
    raise __MODULE__.DecodeError, message: "#{path}: file is empty or contains only comments"
  end

  defp unwrap!({:__block__, _meta, [single]}, _path), do: single

  defp unwrap!({:__block__, _meta, many}, path) do
    raise __MODULE__.DecodeError,
      message: "#{path}: expected exactly one expression, got #{length(many)}"
  end

  defp unwrap!(ast, _path), do: ast

  defp literal!({:%{}, _meta, pairs}, path) do
    Map.new(pairs, fn {key, value} -> {literal!(key, path), literal!(value, path)} end)
  end

  defp literal!({:{}, _meta, elements}, path) do
    elements |> Enum.map(&literal!(&1, path)) |> List.to_tuple()
  end

  # `module: MyApp` in target.exs parses as an alias. Module.concat/1 interns
  # an atom; the input is a project's own config file, one alias per read.
  defp literal!({:__aliases__, _meta, segments}, _path), do: Module.concat(segments)

  defp literal!({left, right}, path), do: {literal!(left, path), literal!(right, path)}

  defp literal!(list, path) when is_list(list), do: Enum.map(list, &literal!(&1, path))

  defp literal!(value, _path) when is_atom(value) or is_binary(value) or is_number(value) do
    value
  end

  # Everything else is a call, not a literal: `-1` is {:-, meta, [1]} and
  # `"x#{y}"` is {:<<>>, ...}. Rejecting them is what makes evaluation absent.
  defp literal!(other, path) do
    raise __MODULE__.DecodeError,
      message: "#{path}: not a literal: #{Macro.to_string(other)}"
  end

  defp ensure_map!(term, _path) when is_map(term), do: term

  defp ensure_map!(term, path) do
    raise __MODULE__.DecodeError,
      message: "#{path}: expected a map at the root, got: #{inspect(term)}"
  end

  defp encodable!(%_struct{} = value) do
    raise __MODULE__.EncodeError, message: "structs are not encodable: #{inspect(value)}"
  end

  defp encodable!(map) when is_map(map) do
    Enum.each(map, fn {key, value} ->
      encodable!(key)
      encodable!(value)
    end)
  end

  defp encodable!(list) when is_list(list), do: Enum.each(list, &encodable!/1)

  defp encodable!(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> Enum.each(&encodable!/1)
  end

  defp encodable!(value) when is_atom(value) or is_binary(value) or is_number(value), do: :ok

  defp encodable!(other) do
    raise __MODULE__.EncodeError, message: "not encodable: #{inspect(other)}"
  end
end

defmodule Capstone.Source.DecodeError do
  @moduledoc "Raised when an .exs file is not the plain data Capstone expects."
  defexception [:message]
end

defmodule Capstone.Source.EncodeError do
  @moduledoc "Raised when a term cannot be written as re-readable .exs source."
  defexception [:message]
end
