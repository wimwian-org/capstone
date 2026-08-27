defmodule Capstone.Config.Project do
  @moduledoc """
  The `project:` section of `target.exs` — the identity of the generated
  project.

  `name` and `github_org` are required. `module` and `app`, when the key is
  absent, are derived from `name` — never from a placeholder — so an
  incomplete `project:` block still produces a config a real project could
  boot with.

  `module` accepts any atom, not only a plausible module alias: telling
  "looks like a real module" from "is any atom" would mean loading the
  module, which a generator must never do (goals.md G6 — nothing here
  evaluates `target.exs`, and loading code is a form of evaluating it).
  """

  alias Capstone.Config.Fields

  @enforce_keys [:name, :module, :app, :github_org]
  defstruct [:name, :module, :app, :github_org]

  @type t :: %__MODULE__{
          name: String.t(),
          module: module(),
          app: atom(),
          github_org: String.t()
        }

  @known_keys ~w(name module app github_org)a
  @required_keys ~w(name github_org)a
  @name_pattern ~r/^[a-z][a-z0-9_]*$/
  @name_description "a lowercase OTP app name matching #{inspect(@name_pattern)}"

  @doc """
  Builds a `t:t/0` from the raw `project:` keyword list, prefixing every
  error path with `path`.
  """
  @spec from_keyword(keyword(), Capstone.Config.path()) ::
          {:ok, t()} | {:error, [Capstone.Config.error()]}
  def from_keyword(fields, path) when is_list(fields) do
    errors =
      Fields.unknown_key_errors(fields, @known_keys, path) ++
        Fields.missing_key_errors(fields, @required_keys, path) ++
        Fields.typed_field_errors(fields, :name, path, @name_description, &valid_name?/1) ++
        Fields.typed_field_errors(
          fields,
          :github_org,
          path,
          "non-empty String.t()",
          &non_empty_string?/1
        ) ++
        Fields.typed_field_errors(fields, :module, path, "module()", &valid_atom?/1) ++
        Fields.typed_field_errors(fields, :app, path, "atom()", &valid_atom?/1)

    case errors do
      [] -> {:ok, build(fields)}
      errors -> {:error, errors}
    end
  end

  defp valid_name?(value), do: is_binary(value) and Regex.match?(@name_pattern, value)
  defp non_empty_string?(value), do: is_binary(value) and value != ""
  defp valid_atom?(value), do: is_atom(value) and not is_nil(value)

  defp build(fields) do
    name = Keyword.fetch!(fields, :name)

    %__MODULE__{
      name: name,
      github_org: Keyword.fetch!(fields, :github_org),
      module: Keyword.get_lazy(fields, :module, fn -> Module.concat([Macro.camelize(name)]) end),
      app:
        Keyword.get_lazy(fields, :app, fn -> name |> Macro.underscore() |> String.to_atom() end)
    }
  end
end
