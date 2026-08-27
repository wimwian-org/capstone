defmodule Capstone.New.Options do
  @moduledoc """
  The `mix capstone.new` argv contract: exactly one switch, `--path`.

  Illegal combinations are unrepresentable: `parse!/1` either returns a fully
  populated struct or raises. `--path` is the only recognised switch — there
  is no NAME positional and no `--base`/`--github-org`/`--module`/`--app`/
  `--capstone-path` any more: `target.exs` (read via `Capstone.Config`, which
  lives in this same project) already carries everything those flags used to
  supply.
  """

  @enforce_keys [:app, :base, :github_org, :module, :name, :capstone, :plugins]
  defstruct [:app, :base, :github_org, :module, :name, :capstone, :plugins]

  @type base :: :otp | :api | :web | :both
  @type dep_source :: {:hex, String.t()} | {:path, Path.t()}
  @type t :: %__MODULE__{
          app: atom(),
          base: base(),
          github_org: String.t(),
          module: module(),
          name: String.t(),
          capstone: dep_source(),
          plugins: [atom()]
        }

  @switches [path: :string]
  @default_requirement "~> 0.1"

  @doc "Parses argv (just `--path PATH`) into a fully validated `%Capstone.New.Options{}`."
  @spec parse!([String.t()]) :: t()
  def parse!(argv) do
    {opts, positional, invalid} = OptionParser.parse(argv, strict: @switches)
    reject_invalid!(invalid)
    reject_positional!(positional)

    opts
    |> fetch_path!()
    |> Capstone.Config.read!()
    |> from_config!()
  end

  @doc """
  Builds a `%Capstone.New.Options{}` from an already-validated `%Capstone.Config{}`.

  `capstone` is always `{:hex, @default_requirement}` here: `target.exs` has
  no dependency-source field — it describes the generated project's
  identity, not the generator's own development conveniences. A `{:path,
  ...}` source stays constructible directly (see `Capstone.New.Factory`'s
  `options_factory/0` and its callers), just not through this function.
  """
  @spec from_config!(Capstone.Config.t()) :: t()
  def from_config!(%Capstone.Config{} = config) do
    %__MODULE__{
      name: config.project.name,
      app: config.project.app,
      module: config.project.module,
      base: config.base,
      github_org: config.project.github_org,
      capstone: {:hex, @default_requirement},
      plugins: config.plugins
    }
  end

  @doc "The Mix task that generates this base's stock project."
  @spec generator(t()) :: String.t()
  def generator(%__MODULE__{base: :otp}), do: "new"
  def generator(%__MODULE__{base: base}) when base in [:api, :web, :both], do: "phx.new"

  @doc """
  The argv to hand the generator.

  `:api`, `:web` and `:both` all produce the SAME stock tree, and that is not
  an oversight: `priv/baselines.exs` records `:web` as `derived_from: :api`
  plus the `:web_layer` plugin, so the asset pipeline arrives when that
  plugin is applied and never from `phx.new`. `:both` follows the identical
  reasoning: it is a project that will eventually carry both layers via
  plugins, not a different stock tree to generate. Generating any of the
  three with HTML and assets here would hand a plugin a tree it did not
  derive against.
  """
  @spec generator_argv(t()) :: [String.t()]
  def generator_argv(%__MODULE__{base: :otp} = opts) do
    [opts.name, "--module", inspect(opts.module), "--app", to_string(opts.app)]
  end

  def generator_argv(%__MODULE__{base: base} = opts) when base in [:api, :web, :both] do
    generator_argv(%{opts | base: :otp}) ++
      ["--no-html", "--no-assets", "--no-install", "--no-version-check"]
  end

  @doc "The dependency line to splice into the generated project's `deps/0`."
  @spec dep_line(t()) :: binary()
  def dep_line(%__MODULE__{capstone: {:path, path}}) do
    ~s|{:capstone, path: "#{path}", only: [:dev], runtime: false}|
  end

  def dep_line(%__MODULE__{capstone: {:hex, requirement}}) do
    ~s|{:capstone, "#{requirement}", only: [:dev], runtime: false}|
  end

  defp reject_invalid!([]), do: :ok

  defp reject_invalid!(invalid) do
    raise __MODULE__.Error,
      message: "unknown switch: #{inspect(Enum.map(invalid, &elem(&1, 0)))}"
  end

  defp reject_positional!([]), do: :ok

  defp reject_positional!(positional) do
    raise __MODULE__.Error,
      message: "mix capstone.new takes no positional arguments, got: #{inspect(positional)}"
  end

  defp fetch_path!(opts) do
    case opts[:path] do
      path when is_binary(path) and path != "" -> path
      _other -> raise __MODULE__.Error, message: "--path is required"
    end
  end
end

defmodule Capstone.New.Options.Error do
  @moduledoc "Raised when `mix capstone.new` is given argv it cannot act on."
  defexception [:message]
end
