defmodule Capstone.Template do
  @moduledoc """
  Converts a meta-project file into a name-agnostic EEx template, and back.

  A meta project must be a real, compiling project with a real name or you
  cannot develop against it. A plugin captured from one must be
  name-agnostic, because it is installed into a project called something else.
  This module is that converter (SDD R1).

  The two directions carry very different risk. `capture/2` must MATCH the
  project name in arbitrary text and can over- or under-reach. `render/2` is a
  pure EEx evaluation with no matching at all. All the danger is in capture,
  and capture only ever runs against meta-project names we choose.

  This module must NOT be merged with `Capstone.Hash`, which strips comments for
  manifest hashing, or `Capstone.Baseline`, which placeholders secrets for drift
  checking. Three normalisers with three different jobs.
  """

  @typedoc "The meta-project's own identity — what `capture/2` matches against and `render/2` substitutes."
  @type names :: %{module: String.t(), app: String.t(), name: String.t()}

  @doc """
  True when `bytes` is valid UTF-8 and may be templated.

  Binary payload takes a verbatim copy path owned by the caller: EEx tokenizes
  a charlist and raises on non-UTF-8 input.
  """
  @spec text?(binary()) :: boolean()
  def text?(bytes), do: String.valid?(bytes)

  @doc "Renders a template back into project source."
  @spec render(binary(), names()) :: binary()
  def render(template, names) do
    EEx.eval_string(template,
      assigns: [module: names.module, app: names.app, name: names.name]
    )
  end

  @doc """
  Replaces the project name inside a PATH with SDD 7.1's bare `APP` placeholder.

  Paths are not EEx. 7.1 spells a plugin's file list `{"lib/APP/cache.ex",
  :sole_owner}`, and a path is low-collision enough that a bare token is safe
  where file content needs a delimited one. The same segment-boundary rule
  applies, so `lib/new_otp_app/cache.ex` becomes `lib/APP/cache.ex` while
  `lib/new_otp_apparatus.ex` is left alone.
  """
  @spec placeholder_path(Path.t(), names()) :: Path.t()
  def placeholder_path(path, names), do: replace_stem(path, names.app, "APP")

  @doc """
  Resolves SDD 7.1's bare `APP` path token against a target project.

  The inverse of `placeholder_path/2`. A plain replacement, not a match: `APP`
  is a token this project wrote, so there is nothing to disambiguate.
  """
  @spec resolve_path(Path.t(), names()) :: Path.t()
  def resolve_path(path, names), do: String.replace(path, "APP", names.app)

  @doc """
  Converts source into a template, verified by rendering it back.

  Returns `{:error, {:render_mismatch, byte_offset}}` when the template does not
  reproduce `source` exactly under the original names.
  """
  @spec capture(binary(), names()) :: {:ok, binary()} | {:error, term()}
  def capture(source, names) do
    if text?(source) do
      source
      |> escape()
      |> substitute(names)
      |> verify(source, names)
    else
      {:error, :binary}
    end
  end

  # `rescue e ->`, never the bare form: BoundaryGuard bans that, and the
  # exception is the only diagnostic a caller gets for an unrenderable template.
  defp verify(template, source, names) do
    case render(template, names) do
      ^source -> {:ok, template}
      other -> {:error, {:render_mismatch, first_difference(source, other)}}
    end
  rescue
    e -> {:error, {:render_raised, Exception.message(e)}}
  end

  # MUST run before substitute/2. Reversed, the openers inserted by substitute/2
  # are themselves escaped and the generated project receives the literal text
  # `<%= @app %>` instead of its own name.
  defp escape(source), do: String.replace(source, "<%", "<%%")

  defp substitute(text, names) do
    text
    |> replace_stem(names.module, "<%= @module %>")
    |> replace_stem(names.app, "<%= @app %>")
  end

  defp replace_stem(text, stem, placeholder) do
    Regex.replace(boundary(stem), text, placeholder)
  end

  # Underscores and CamelCase humps are segment SEPARATORS, not identifier
  # interiors. The left boundary rejects only alphanumerics, so a leading `_`
  # separates too — `_new_web_app_key`, the session cookie, depends on it.
  #
  # `new_web_app_dev`  matches: `_dev` is a delimited continuation.
  # `my_comparison`    does not: `arison` is not delimited.
  #
  # Regex.escape/1 is not optional: `name` can legitimately be ".", per SDD 8.1.
  defp boundary(stem) do
    Regex.compile!("(?<![A-Za-z0-9])" <> Regex.escape(stem) <> "(?![a-z0-9])")
  end

  defp first_difference(a, b) do
    limit = min(byte_size(a), byte_size(b))
    found = Enum.find(0..(limit - 1)//1, &(binary_part(a, &1, 1) != binary_part(b, &1, 1)))

    found || limit
  end
end
