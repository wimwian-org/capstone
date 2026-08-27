defmodule Capstone.Config.Literal do
  @moduledoc """
  Parses Elixir source into a plain term without ever evaluating it.

  `target.exs` is data, not code (goals.md G6): reading it must never
  evaluate it via `Code`'s `eval_string/1` or `eval_file/1`, because doing
  so would execute whatever its author — or a compromised generator —
  chose to put there. `from_source/1` calls `Code.string_to_quoted/1`
  (parse, not evaluate) and walks the resulting AST, reconstructing only a fixed
  whitelist of literal shapes: maps with atom keys, lists (plain or
  keyword), module aliases, atoms, binaries, and integers. Anything else —
  a function call, a variable, an operator, string interpolation, a sigil
  — is rejected before it is ever reduced to a value.

  **Accepted risk, not a gap:** `Code.string_to_quoted/1` itself interns
  an atom for every atom literal and module alias in `source` — this
  module never disables that (no `static_atoms_encoder:`), and
  `Module.concat/1` mints one more per alias it reconstructs. G6's
  property is "never evaluates `target.exs`"; atom-table exhaustion is a
  different property this module does not claim. For a CLI reading one
  local, developer-authored file per invocation that is not a live
  threat — the concern is a server parsing unbounded attacker input on
  every request, not this. If that trust model ever changes,
  `static_atoms_encoder:` is the mechanism to reach for.
  """

  @type path :: [atom() | non_neg_integer()]
  @type error ::
          {:syntax_error, line :: pos_integer(), description :: String.t()}
          | {:not_literal, path(), quoted :: Macro.t()}
          | {:duplicate_key, path(), key :: atom()}

  @doc """
  Parses `source` and reconstructs it as a plain Elixir term.
  """
  @spec from_source(String.t()) :: {:ok, term()} | {:error, error()}
  def from_source(source) when is_binary(source) do
    case Code.string_to_quoted(source) do
      {:ok, quoted} ->
        walk(quoted, [])

      {:error, {location, description, token}} ->
        {:error, {:syntax_error, line(location), description(description) <> token}}
    end
  end

  defp line(location) when is_list(location), do: Keyword.fetch!(location, :line)

  # `Code.string_to_quoted/1`'s error description is `binary() |
  # {binary(), binary()}` — the tuple form carries a reserved-word hint
  # (e.g. `{"unexpected reserved word: ", "end"}`) that `to_string/1`
  # cannot handle on its own. The offending token itself is appended
  # separately, above, so a message like "unexpected reserved word: "
  # doesn't trail off into nothing.
  defp description({prefix, suffix}), do: prefix <> suffix
  defp description(binary) when is_binary(binary), do: binary

  defp walk({:%{}, _meta, pairs}, path) when is_list(pairs), do: walk_pairs(pairs, path, %{})

  defp walk({:__aliases__, _meta, parts}, _path) when is_list(parts),
    do: {:ok, Module.concat(parts)}

  defp walk(list, path) when is_list(list), do: walk_list(list, path, 0, [])

  defp walk(literal, _path) when is_atom(literal) or is_binary(literal) or is_integer(literal) do
    {:ok, literal}
  end

  defp walk(other, path), do: {:error, {:not_literal, Enum.reverse(path), other}}

  defp walk_pairs([], _path, acc), do: {:ok, acc}

  defp walk_pairs([{key, _value} | _rest], path, acc)
       when is_atom(key) and is_map_key(acc, key) do
    {:error, {:duplicate_key, Enum.reverse(path), key}}
  end

  defp walk_pairs([{key, value} | rest], path, acc) when is_atom(key) do
    with {:ok, value} <- walk(value, [key | path]) do
      walk_pairs(rest, path, Map.put(acc, key, value))
    end
  end

  defp walk_pairs([{key, _value} | _rest], path, _acc) do
    {:error, {:not_literal, Enum.reverse(path), key}}
  end

  # Anything in the pairs list that isn't a plain 2-tuple — e.g. the `{:|,
  # meta, [...]}` node from map-update syntax `%{x | a: 1}` — is rejected
  # here rather than crashing `walk_pairs/3` with a `FunctionClauseError`.
  defp walk_pairs([other | _rest], path, _acc) do
    {:error, {:not_literal, Enum.reverse(path), other}}
  end

  defp walk_list([], _path, _index, acc), do: {:ok, Enum.reverse(acc)}

  defp walk_list([{key, value} | rest], path, index, acc) when is_atom(key) do
    if List.keymember?(acc, key, 0) do
      {:error, {:duplicate_key, Enum.reverse(path), key}}
    else
      with {:ok, value} <- walk(value, [key | path]) do
        walk_list(rest, path, index + 1, [{key, value} | acc])
      end
    end
  end

  defp walk_list([element | rest], path, index, acc) do
    with {:ok, element} <- walk(element, [index | path]) do
      walk_list(rest, path, index + 1, [element | acc])
    end
  end
end
