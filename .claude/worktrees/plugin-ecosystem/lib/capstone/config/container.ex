defmodule Capstone.Config.Container.Sidecars do
  @moduledoc """
  The `container: [sidecars: ...]` sub-section of `target.exs`. Every key
  is optional and defaults to `false`.
  """

  alias Capstone.Config.Fields

  defstruct valkey: false, openbao: false, nginx: false

  @type t :: %__MODULE__{valkey: boolean(), openbao: boolean(), nginx: boolean()}

  @known_keys ~w(valkey openbao nginx)a

  @doc """
  Builds a `t:t/0` from the raw `sidecars:` keyword list, prefixing every
  error path with `path`.
  """
  @spec from_keyword(keyword(), Capstone.Config.path()) ::
          {:ok, t()} | {:error, [Capstone.Config.error()]}
  def from_keyword(fields, path) when is_list(fields) do
    unknown = Fields.unknown_key_errors(fields, @known_keys, path)
    type_errors = Enum.flat_map(@known_keys, &Fields.boolean_field_errors(fields, &1, path))

    case unknown ++ type_errors do
      [] ->
        {:ok,
         %__MODULE__{
           valkey: Keyword.get(fields, :valkey, false),
           openbao: Keyword.get(fields, :openbao, false),
           nginx: Keyword.get(fields, :nginx, false)
         }}

      errors ->
        {:error, errors}
    end
  end
end

defmodule Capstone.Config.Container do
  @moduledoc """
  The `container:` section of `target.exs`.

  `local_ci` is the one field in this whole section family that defaults
  to `true` rather than `false` — every sidecar, and every boolean in
  `Security`, defaults off; local CI defaults on.
  """

  alias Capstone.Config.Container.Sidecars
  alias Capstone.Config.Fields

  defstruct local_ci: true, sidecars: %Sidecars{}

  @type t :: %__MODULE__{local_ci: boolean(), sidecars: Sidecars.t()}

  @known_keys ~w(local_ci sidecars)a

  @doc """
  Builds a `t:t/0` from the raw `container:` keyword list, prefixing every
  error path with `path`.
  """
  @spec from_keyword(keyword(), Capstone.Config.path()) ::
          {:ok, t()} | {:error, [Capstone.Config.error()]}
  def from_keyword(fields, path) when is_list(fields) do
    unknown = Fields.unknown_key_errors(fields, @known_keys, path)
    local_ci_errors = Fields.boolean_field_errors(fields, :local_ci, path)
    {sidecars, sidecars_errors} = sidecars_result(fields, path)

    case unknown ++ local_ci_errors ++ sidecars_errors do
      [] -> {:ok, %__MODULE__{local_ci: Keyword.get(fields, :local_ci, true), sidecars: sidecars}}
      errors -> {:error, errors}
    end
  end

  defp sidecars_result(fields, path) do
    case Keyword.fetch(fields, :sidecars) do
      {:ok, value} when is_list(value) -> split(Sidecars.from_keyword(value, path ++ [:sidecars]))
      {:ok, other} -> {%Sidecars{}, [{:invalid_type, path ++ [:sidecars], "keyword list", other}]}
      :error -> {%Sidecars{}, []}
    end
  end

  defp split({:ok, sidecars}), do: {sidecars, []}
  defp split({:error, errors}), do: {%Sidecars{}, errors}
end
