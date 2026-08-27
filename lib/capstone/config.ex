defmodule Capstone.Config do
  @moduledoc """
  Reads and validates a project's `target.exs` — the hand-authored record
  of what a project asked Capstone for (goals.md D16).

  Every read goes through `Capstone.Config.Literal`, never `Code.eval_*`:
  `target.exs` is data, not code, per goals.md G6. Validation does not stop
  at the first problem — `read/1` and `read_string/1` return every error
  found, so a `target.exs` with three mistakes reports three.
  """

  alias Capstone.Config.Container
  alias Capstone.Config.Error
  alias Capstone.Config.Fields
  alias Capstone.Config.Literal
  alias Capstone.Config.Project
  alias Capstone.Config.Security

  @typedoc "A location inside a parsed `target.exs`, as a list of map/keyword keys and list indices from the root."
  @type path :: Literal.path()

  @typedoc "Every reason `read/1`, `read_string/1` and their bang variants can fail."
  @type error ::
          {:file_error, File.posix()}
          | Literal.error()
          | {:not_a_map, term()}
          | {:missing_key, path()}
          | {:unknown_key, path(), atom()}
          | {:invalid_type, path(), String.t(), term()}
          | {:invalid_value, path(), [term()], term()}
          | {:unsupported_schema_version, term()}

  @enforce_keys [:schema_version, :base, :plugins, :project, :security, :container]
  defstruct [:schema_version, :base, :plugins, :project, :security, :container]

  @type t :: %__MODULE__{
          schema_version: pos_integer(),
          base: :api | :web | :both,
          plugins: [atom()],
          project: Project.t(),
          security: Security.t(),
          container: Container.t()
        }

  @known_keys ~w(schema_version base plugins project security container)a
  @required_keys ~w(schema_version base plugins project)a
  @valid_bases ~w(api web both)a

  @doc "Reads and validates the `target.exs` at `path`."
  @spec read(Path.t()) :: {:ok, t()} | {:error, [error()]}
  def read(path) do
    case File.read(path) do
      {:ok, source} -> read_string(source)
      {:error, reason} -> {:error, [{:file_error, reason}]}
    end
  end

  @doc "As `read/1`, raising `Capstone.Config.Error` on any validation failure."
  @spec read!(Path.t()) :: t()
  def read!(path), do: path |> read() |> unwrap!()

  @doc "Parses and validates `source` as `target.exs` content, without touching the filesystem."
  @spec read_string(String.t()) :: {:ok, t()} | {:error, [error()]}
  def read_string(source) when is_binary(source) do
    case Literal.from_source(source) do
      {:ok, term} -> validate(term)
      {:error, reason} -> {:error, [reason]}
    end
  end

  @doc "As `read_string/1`, raising `Capstone.Config.Error` on any validation failure."
  @spec read_string!(String.t()) :: t()
  def read_string!(source), do: source |> read_string() |> unwrap!()

  defp unwrap!({:ok, config}), do: config
  defp unwrap!({:error, errors}), do: raise(Error, errors: errors)

  defp validate(term) when is_map(term) do
    {project, project_errors} = section(term, :project, &Project.from_keyword/2)

    {security, security_errors} =
      section_with_default(term, :security, &Security.from_keyword/2, %Security{})

    {container, container_errors} =
      section_with_default(term, :container, &Container.from_keyword/2, %Container{})

    errors =
      Fields.unknown_key_errors(term, @known_keys, []) ++
        Fields.missing_key_errors(term, @required_keys, []) ++
        scalar_errors(term) ++
        project_errors ++ security_errors ++ container_errors

    case errors do
      [] ->
        {:ok,
         %__MODULE__{
           schema_version: term.schema_version,
           base: term.base,
           plugins: term.plugins,
           project: project,
           security: security,
           container: container
         }}

      errors ->
        {:error, errors}
    end
  end

  defp validate(term), do: {:error, [{:not_a_map, term}]}

  defp section(term, key, builder) do
    case Map.fetch(term, key) do
      {:ok, value} when is_list(value) -> split(builder.(value, [key]))
      {:ok, other} -> {nil, [{:invalid_type, [key], "keyword list", other}]}
      :error -> {nil, []}
    end
  end

  defp section_with_default(term, key, builder, default) do
    case Map.fetch(term, key) do
      {:ok, value} when is_list(value) -> split(builder.(value, [key]))
      {:ok, other} -> {default, [{:invalid_type, [key], "keyword list", other}]}
      :error -> {default, []}
    end
  end

  defp split({:ok, struct}), do: {struct, []}
  defp split({:error, errors}), do: {nil, errors}

  defp scalar_errors(term) do
    schema_version_errors(term) ++ base_errors(term) ++ plugins_errors(term)
  end

  defp schema_version_errors(term) do
    case Map.fetch(term, :schema_version) do
      {:ok, 1} -> []
      {:ok, other} -> [{:unsupported_schema_version, other}]
      :error -> []
    end
  end

  defp base_errors(term) do
    case Map.fetch(term, :base) do
      {:ok, base} when base in @valid_bases -> []
      {:ok, other} -> [{:invalid_value, [:base], @valid_bases, other}]
      :error -> []
    end
  end

  defp plugins_errors(term) do
    case Map.fetch(term, :plugins) do
      {:ok, plugins} when is_list(plugins) ->
        if Enum.all?(plugins, &is_atom/1),
          do: [],
          else: [{:invalid_value, [:plugins], ["a list of atoms"], plugins}]

      {:ok, other} ->
        [{:invalid_value, [:plugins], ["a list of atoms"], other}]

      :error ->
        []
    end
  end
end
