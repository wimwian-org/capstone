defmodule Capstone.Plugin.Behavior do
  @moduledoc """
  The contract a plugin implements.

  A plugin installs one infrastructure concern into a generated project — a
  cache, a container runtime, a vault, an auth stack — and knows nothing about
  what the project is for. Most of a plugin is *data*: the files it owns, the
  dependencies it needs, the capabilities it requires and provides. Only two
  callbacks are code, and both are escape hatches.

  This behaviour is public and stable from day one because a plugin may live in
  a separate repository and must install without editing Capstone's source (R4).

  ## Defining a plugin

      defmodule MyOrg.Valkey do
        use Capstone.Plugin.Behavior, name: :valkey, version: "1.3.0"

        @impl true
        def files(_config) do
          [
            {"lib/APP/cache.ex", :sole_owner},
            {"compose.yaml", :contributes, key: :valkey_service}
          ]
        end

        @impl true
        def deps, do: [{:nebulex, "~> 3.0"}]

        @impl true
        def requires, do: [:container_runtime]
      end

  `name/0` and `version/0` come from the `use` options. `files/1` must be
  implemented. `deps/0`, `requires/0`, `provides/0` and `conflicts/0` default to
  `[]` and are overridable. `transform/2` and `upgrade/3` are optional.

  ## Why so little of it is code

  `deps/0` is a declared list rather than something read back out of the
  plugin's own `mix.exs` (D10). A plugin that reflects its own project copies
  `in_umbrella: true` and path deps straight into the target and breaks it.

  Everything a plugin returns must be deterministic — the same inputs must
  produce the same bytes today and in eighteen months, because an update
  regenerates a historical version and diffs it (D8). No timestamps, no
  randomness, no map iteration order leaking into output.

  ## The two escape hatches, and how they must fail

  `transform/2` and `upgrade/3` exist for what the file list cannot express.
  Both must **let exceptions propagate**. Never wrap the body in a bare
  `rescue`.

  This is not style. Fireside swallowed exceptions from its equivalents in a
  bare `rescue` and bumped the recorded version anyway, so a transform that did
  nothing was recorded as having succeeded — the manifest became a claim rather
  than a fact. Capstone records a version only after every step actually succeeded
  (G5), and that is only true if failure is loud.
  """

  import Capstone.Vendor.SimpleEnum, only: [defenum: 2]

  @typedoc "The plugin's identity — unique within a project."
  @type name :: atom()

  @typedoc "A semver string. Integers are not accepted (D5)."
  @type version :: String.t()

  @typedoc "A named capability, used to resolve ordering and conflicts."
  @type capability :: atom()

  # Declared with SimpleEnum rather than as a bare union so the three modes come
  # with membership guards (`is_mode_key/1`) and an authoritative `mode_keys/0`
  # list. A loader validating a plugin manifest -- which by D20 has no compile
  # step to catch a typo -- needs exactly that, and a union type gives it
  # nothing at runtime.
  #
  #   * `:sole_owner`  — exactly one plugin writes this path
  #   * `:contributes` — many plugins contribute to one file, located by `:key`
  #   * `:seed`        — written once at generation and never touched again
  #
  # Generates `mode/1`, `mode/2`, `mode_keys/0`, `mode_values/0`,
  # `mode_enumerators/0` and the `is_mode*/1` guards, plus the `mode`,
  # `mode_keys` and `mode_values` types.
  defenum(:mode, [:sole_owner, :contributes, :seed])

  @typedoc """
  A file the plugin writes.

  The options carry `:key` for a `:contributes` entry's idempotency key, and
  `:when` to restrict the entry to one base, as in `when: [base: :web]`.
  """
  @type file_spec :: {Path.t(), mode_keys()} | {Path.t(), mode_keys(), keyword()}

  @typedoc "A dependency to add to the *target* project, never to the plugin."
  @type dep :: {atom(), String.t()} | {atom(), String.t(), keyword()}

  @typedoc "The resolved contents of the project's `target.exs`."
  @type config :: map()

  @typedoc "An explicit path to the generated project's root."
  @type root :: Path.t()

  @doc "The plugin's identity. Supplied by `use Capstone.Plugin.Behavior, name: ...`."
  @callback name() :: name()

  @doc "The plugin's semver version. Supplied by `use Capstone.Plugin.Behavior, version: ...`."
  @callback version() :: version()

  @doc "Every file this plugin writes, with its ownership mode."
  @callback files(config()) :: [file_spec()]

  @doc "Dependencies to add to the target project. Defaults to `[]`."
  @callback deps() :: [dep()]

  @doc "Capabilities this plugin needs from others. Defaults to `[]`."
  @callback requires() :: [capability()]

  @doc "Capabilities this plugin satisfies for others. Defaults to `[]`."
  @callback provides() :: [capability()]

  @doc "Capabilities this plugin cannot coexist with. Defaults to `[]`."
  @callback conflicts() :: [capability()]

  @doc """
  Anything the file list cannot express, run at install time.

  Must raise on failure — see the module documentation.
  """
  @callback transform(root(), config()) :: :ok

  @doc """
  Migrate a project from one version of this plugin to another.

  Must raise on failure — see the module documentation.
  """
  @callback upgrade(root(), version(), version()) :: :ok

  @optional_callbacks transform: 2, upgrade: 3

  @doc """
  Declares the module a plugin.

  Requires `:name` (an atom) and `:version` (a semver string), and supplies
  overridable `deps/0`, `requires/0`, `provides/0` and `conflicts/0` returning
  `[]`. Both options are validated at compile time, so a malformed plugin fails
  when it is built rather than when a project tries to install it.
  """
  defmacro __using__(opts) do
    name = fetch!(opts, :name)
    version = opts |> fetch!(:version) |> validate_version!()

    quote do
      @behaviour Capstone.Plugin.Behavior

      @impl true
      def name, do: unquote(name)

      @impl true
      def version, do: unquote(version)

      @impl true
      def deps, do: []

      @impl true
      def requires, do: []

      @impl true
      def provides, do: []

      @impl true
      def conflicts, do: []

      defoverridable deps: 0, requires: 0, provides: 0, conflicts: 0
    end
  end

  defp fetch!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} ->
        value

      :error ->
        raise ArgumentError,
              "use Capstone.Plugin.Behavior requires #{inspect(key)}; a plugin without one cannot be " <>
                "recorded in plugin.exs, so it could never be updated"
    end
  end

  defp validate_version!(version) when is_binary(version) do
    case Version.parse(version) do
      {:ok, _parsed} ->
        version

      :error ->
        raise ArgumentError,
              "use Capstone.Plugin.Behavior expects :version to be a semver string, got #{inspect(version)}; " <>
                "integer schemes cannot express a range and would strand this plugin (D5)"
    end
  end

  defp validate_version!(version) do
    raise ArgumentError,
          "use Capstone.Plugin.Behavior expects :version to be a semver string, got #{inspect(version)}; " <>
            "integer schemes cannot express a range and would strand this plugin (D5)"
  end
end
