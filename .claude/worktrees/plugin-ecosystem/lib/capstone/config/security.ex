defmodule Capstone.Config.Security do
  @moduledoc """
  The `security:` section of `target.exs`. Every key is optional and
  defaults to `false`.
  """

  alias Capstone.Config.Fields

  defstruct envelope_encryption: false, cloak: false

  @type t :: %__MODULE__{envelope_encryption: boolean(), cloak: boolean()}

  @known_keys ~w(envelope_encryption cloak)a

  @doc """
  Builds a `t:t/0` from the raw `security:` keyword list, prefixing every
  error path with `path`.
  """
  @spec from_keyword(keyword(), Capstone.Config.path()) ::
          {:ok, t()} | {:error, [Capstone.Config.error()]}
  def from_keyword(fields, path) when is_list(fields) do
    errors =
      Fields.unknown_key_errors(fields, @known_keys, path) ++
        Fields.boolean_field_errors(fields, :envelope_encryption, path) ++
        Fields.boolean_field_errors(fields, :cloak, path)

    case errors do
      [] ->
        {:ok,
         %__MODULE__{
           envelope_encryption: Keyword.get(fields, :envelope_encryption, false),
           cloak: Keyword.get(fields, :cloak, false)
         }}

      errors ->
        {:error, errors}
    end
  end
end
