defmodule Capstone.Hash do
  @moduledoc """
  Content hashing for manifest file entries.

  For `.ex`/`.exs`, normalisation is `Code.string_to_quoted!/2 |>
  Macro.to_string/1`: the parser discards comments and the printer
  canonicalises whitespace, so reindentation and an added
  `# credo:disable-for-next-line` produce the SAME hash. That is the guarantee
  the whole design exists for.

  Capstone.Vendor.Sourceror is the wrong tool and was measured: `Sourceror.to_string/1`
  reproduces comments verbatim (they live in `leading_comments`/
  `trailing_comments` metadata), and `Sourceror.Comments.extract_comments/1`
  also fails, because removing a comment node removes its `previous_eol_count`
  and changes blank-line rendering. Hashing the AST term directly
  (`:erlang.term_to_binary/1`, `:erlang.phash2/1`, `inspect/1`) is likewise
  wrong: `line:` metadata SHIFTS when comments are added. The
  comment-insensitivity comes from `Macro.to_string/1` discarding metadata, not
  from the parser.

  ## The normalised string is a HASH INPUT ONLY

  It is not guaranteed to be valid Elixir — a string literal containing both
  interpolation and a `\\r` escape is rendered with a raw carriage return that
  will not re-parse — and `Macro.to_string/1` is not idempotent. Never write it
  to disk, never re-parse it, never re-normalise it.

  ## Known MVP limitations

  Non-Elixir files stay comment-SENSITIVE: a `# added by user` in a
  `compose.yaml` DOES change its hash. Semantics-preserving literal rewrites
  collide for Elixir files (`0x1F` vs `31`, `?a` vs `97`, `1_000_000` vs
  `1000000`, heredoc vs escaped string). An empty file and a comments-only file
  share a hash.

  Whitespace inside a multi-line sigil or heredoc is literal content, not
  layout — a sigil keeps its interior verbatim and a heredoc measures its
  interior against the closing delimiter — so reindenting a `~w(...)` block, an
  `~H` template or an indented code sample inside a `@moduledoc` DOES change the
  hash. `mix format` preserves those interiors; a manual or editor block
  reindent does not.

  This module must NOT share a normaliser with `Capstone.Baseline`, which
  requires the opposite semantics.
  """

  @elixir_extensions ~w(.ex .exs)

  # U+FEFF as its UTF-8 bytes: written as the character itself it is invisible
  # in every editor and diff, and silently survives nothing.
  @bom <<0xEF, 0xBB, 0xBF>>

  @doc "Normalises file bytes for hashing, dispatching strictly on the extension."
  @spec normalise(binary(), Path.t()) :: binary()
  def normalise(content, path) do
    content
    |> strip_bom()
    |> normalise_for(Path.extname(path), path)
  end

  @doc ~S|Returns `"sha256:"` followed by 64 lowercase hex characters.|
  @spec content_hash(binary(), Path.t()) :: binary()
  def content_hash(content, path), do: digest(normalise(content, path))

  @doc """
  Hashes `content` as opaque TEXT, whatever extension its path claims.

  For a file that is not the language its name promises — an `.ex` carrying an
  unresolved conflict region, which `mix capstone.check` gates — the parser
  raises, and a recorder that has just written that file needs a hash rather
  than an exception.

  The CALL SITE decides, on a fact it already knows. `content_hash/2` stays
  strictly extension-dispatched and never try-parses-then-falls-back, for the
  reason its own test names: under a fallback scheme the same bytes hash
  differently depending on whether they happen to be valid Elixir, so
  introducing a syntax error would silently flip a file's hashing mode and could
  mask a divergence.
  """
  @spec text_hash(binary()) :: binary()
  def text_hash(content), do: content |> strip_bom() |> as_text() |> digest()

  defp digest(normalised) do
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, normalised), case: :lower)
  end

  defp normalise_for(content, extension, path) when extension in @elixir_extensions do
    content
    |> Code.string_to_quoted!(file: path, emit_warnings: false)
    |> Macro.to_string()
  end

  defp normalise_for(content, _extension, _path), do: as_text(content)

  defp as_text(content) do
    content
    |> String.replace("\r\n", "\n")
    |> String.split("\n")
    |> Enum.map_join("\n", &String.trim_trailing/1)
    |> String.trim_trailing("\n")
  end

  defp strip_bom(@bom <> rest), do: rest
  defp strip_bom(content), do: content
end
