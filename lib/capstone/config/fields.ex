defmodule Capstone.Config.Fields do
  @moduledoc """
  Shared validation primitives for `target.exs` section keyword lists.

  `Project`, `Security`, `Container` and `Sidecars` each apply the same
  "flag unknown keys, flag missing required keys, check each present
  key's type" shape to their own field set — and `Capstone.Config` itself
  applies the first two of those to its own top-level keys. This module
  is the one place that shape is written, so every caller differs only in
  which keys it knows about and which predicate each field must satisfy
  — not in how a fetch/check/report cycle works.

  `unknown_key_errors/3` and `missing_key_errors/3` accept either a
  keyword list (every section module's `fields`) or a map
  (`Capstone.Config`'s own top-level term, straight from
  `Capstone.Config.Literal`) — both enumerate as `{key, value}` pairs,
  and neither function needs more than that. `typed_field_errors/5` and
  `boolean_field_errors/3` are keyword-list-only: they call
  `Keyword.fetch/2`, which only the four section modules need, since
  `Capstone.Config`'s own scalar fields (`schema_version`, `base`,
  `plugins`) each have bespoke validation rules, not a shared predicate.
  """

  @typedoc "Re-exported for callers that only need `Fields`; see `Capstone.Config.Literal.path/0`."
  @type path :: Capstone.Config.Literal.path()

  @doc """
  Every key in `fields` not present in `known_keys`, as
  `{:unknown_key, path, key}`.
  """
  @spec unknown_key_errors(keyword() | map(), [atom()], path()) :: [Capstone.Config.error()]
  def unknown_key_errors(fields, known_keys, path) do
    for {key, _value} <- fields, key not in known_keys, do: {:unknown_key, path, key}
  end

  @doc """
  Every key in `required_keys` absent from `fields`, as
  `{:missing_key, path ++ [key]}`.
  """
  @spec missing_key_errors(keyword() | map(), [atom()], path()) :: [Capstone.Config.error()]
  def missing_key_errors(fields, required_keys, path) do
    present = for {key, _value} <- fields, into: MapSet.new(), do: key
    for key <- required_keys, key not in present, do: {:missing_key, path ++ [key]}
  end

  @doc """
  When `key` is present in `fields` and `valid?` rejects its value, one
  `{:invalid_type, path ++ [key], description, value}` error. `[]`
  otherwise — including when `key` is absent, since absence is a
  `missing_key_errors/3` concern, not a type concern.
  """
  @spec typed_field_errors(keyword(), atom(), path(), String.t(), (term() -> boolean())) ::
          [Capstone.Config.error()]
  def typed_field_errors(fields, key, path, description, valid?) do
    case Keyword.fetch(fields, key) do
      {:ok, value} ->
        if valid?.(value), do: [], else: [{:invalid_type, path ++ [key], description, value}]

      :error ->
        []
    end
  end

  @doc "As `typed_field_errors/5`, with `is_boolean/1` as the predicate and `\"boolean()\"` as the description."
  @spec boolean_field_errors(keyword(), atom(), path()) :: [Capstone.Config.error()]
  def boolean_field_errors(fields, key, path) do
    typed_field_errors(fields, key, path, "boolean()", &is_boolean/1)
  end
end
