defmodule Capstone.Factory do
  @moduledoc false

  use ExMachina

  alias Capstone.Hash
  alias Capstone.Manifest
  alias Capstone.Manifest.FileEntry
  alias Capstone.Manifest.Plugin

  @default_elixir_source_variety :plain
  @default_timestamp "2026-08-11T00:00:00Z"

  # Real content of two NON-Elixir extensions, so a manifest file entry's hash
  # comes from Capstone.Hash over bytes of the kind the path claims. A literal
  # "sha256:..." would let every round-trip pass without the hasher ever running.
  @compose_yaml "services:\n  valkey:\n    image: valkey/valkey:8\n"
  @seed_css ~s|@import "tailwindcss";\n|

  @doc """
  A `%Capstone.Manifest{}` in CANONICAL order — the manifest round-trip corpus.

  Plugins are listed sorted by `name` and their files sorted by `path`,
  because `read!/1` returns what `write!/2` sorted and the round-trip test
  compares the two for equality. Reordering these for readability breaks that
  test with an opaque diff.

  Two origin shapes, deliberately: the relative-`{:path, _}` branch of the
  origin check is otherwise reachable only from the test asserting an ABSOLUTE
  path raises, which never runs it.
  """
  @spec manifest_factory() :: Manifest.t()
  def manifest_factory do
    %Manifest{
      base: :web,
      plugins: [
        build(:manifest_component,
          name: :tailwind,
          origin: {:path, "priv/plugins/tailwind"},
          version: "0.4.2",
          files: [seed_file()]
        ),
        build(:manifest_component, name: :valkey)
      ],
      config_digest: digest("a"),
      generated_at: @default_timestamp,
      schema_version: 1,
      capstone_version: "1.0.0"
    }
  end

  @doc """
  A `%Capstone.Manifest.Plugin{}` owning one file and contributing to another.

  Arity-0 only, as `:manifest` and `:file_entry` are: ExMachina calls an
  arity-1 factory INSTEAD of `merge_attributes/2`, so an arity-1 clause here
  would make every `build(:manifest_component, name: ...)` in the suite
  silently ignore its attributes.

  `name` is sequenced because three plugins built from this factory must not
  collide — the reversed-order byte-identity test would raise `duplicate
  plugin names` before it could compare anything.
  """
  @spec manifest_component_factory() :: Plugin.t()
  def manifest_component_factory do
    %Plugin{
      applied_at: @default_timestamp,
      files: [contributed_file(), build(:file_entry)],
      name: sequence(:manifest_component_name, &:"component_#{&1}"),
      origin: {:hex, "capstone_valkey", "1.3.0"},
      version: "1.3.0"
    }
  end

  @doc """
  A `%Capstone.Manifest.FileEntry{}` for an `.ex` file the plugin owns.

  `:sole_owner` with `key: nil` is the default deliberately: attributes merge
  over this entry, so a test overriding only `mode:` must not inherit a stale
  key that makes the entry invalid for a reason it never asked for.
  """
  @spec file_entry_factory() :: FileEntry.t()
  def file_entry_factory do
    path = "lib/my_app/cache.ex"
    %{source: source} = elixir_source(@default_elixir_source_variety)

    %FileEntry{hash: Hash.content_hash(source, path), key: nil, mode: :sole_owner, path: path}
  end

  # The two entries `:file_entry`'s defaults cannot express: a :contributes one
  # (which REQUIRES a key) and a :seed one. "compose.yaml" sorts before
  # "lib/my_app/cache.ex", which is what makes `:manifest_component`'s file list
  # canonical as written.
  defp contributed_file do
    path = "compose.yaml"

    %FileEntry{
      hash: Hash.content_hash(@compose_yaml, path),
      key: :valkey_service,
      mode: :contributes,
      path: path
    }
  end

  defp seed_file do
    path = "assets/css/app.css"

    %FileEntry{hash: Hash.content_hash(@seed_css, path), key: nil, mode: :seed, path: path}
  end

  # Unpadded base64, the alphabet phx.new's `crypto:strong_rand_bytes` values
  # really use: both carry a `+` and a `/` so a `[A-Za-z0-9]` matcher misses them.
  @default_secret_key_base "Dhz/sfYIpwn0QjTruV0kBlfcxxHOeakb9CSQD6I4DHriAIhPmV/gak+2lOjVRF6m"
  @default_signing_salt "QZo+K6/D"

  # `.formatter.exs` is the load-bearing entry: it is the dotfile a
  # `match_dot: false` walk would silently drop, and the only positive control
  # in a test whose other assertions an empty tree would satisfy.
  @baseline_tree_files %{
    ".formatter.exs" => "[inputs: [\"mix.exs\"]]\n",
    ".git/config" => "[core]\n\trepositoryformatversion = 0\n",
    "README.md" => "# BaselineTree\n",
    "_build/dev/lib/app/ebin/app.app" => "{application,app,[]}.\n",
    "deps/foo/mix.exs" => "defmodule Foo.MixProject do\nend\n",
    "lib/app.ex" => "defmodule App do\nend\n",
    "mix.exs" => "defmodule App.MixProject do\nend\n"
  }

  @doc "A phx.new config source carrying both randomised secrets."
  @spec phx_config_source_factory() :: %{secret: String.t(), source: String.t()}
  def phx_config_source_factory, do: phx_config_source(@default_secret_key_base)

  @doc "The same source, built around a caller-supplied secret value."
  @spec phx_config_source_factory(map()) :: %{secret: String.t(), source: String.t()}
  def phx_config_source_factory(%{secret: secret}), do: phx_config_source(secret)

  def phx_config_source_factory(attrs) when map_size(attrs) == 0,
    do: phx_config_source(@default_secret_key_base)

  defp phx_config_source(secret) do
    source = """
    config :new_web_app, NewWebAppWeb.Endpoint,
      secret_key_base: "#{secret}",
      live_view: [signing_salt: "#{@default_signing_salt}"]
    """

    %{secret: secret, source: source}
  end

  @doc "A throwaway directory shaped like a generated project, prunable dirs included."
  @spec baseline_tree_factory() :: %{path: Path.t()}
  def baseline_tree_factory do
    path = Path.join(System.tmp_dir!(), "baseline-tree-#{System.unique_integer([:positive])}")

    Enum.each(@baseline_tree_files, fn {relative, contents} ->
      file = Path.join(path, relative)
      File.mkdir_p!(Path.dirname(file))
      File.write!(file, contents)
    end)

    # Cleanup belongs with creation, not with the caller: the factory-shape guard
    # builds every arity-0 factory and cannot know this one touched the disk.
    # `build/1` runs in the test process, which is where on_exit/1 registers.
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(path) end)

    %{path: path}
  end

  # One addition per bucket, so a classifier that collapses two of them fails.
  @meta_pair_baseline %{
    "mix.exs" =>
      "defmodule App.MixProject do\n  defp deps do\n    [\n      {:jason, \"~> 1.4\"}\n    ]\n  end\nend\n",
    "config/config.exs" => "import Config\n\nconfig :app, key: :value\n",
    "lib/app/application.ex" =>
      "defmodule App.Application do\n  def start(_, _) do\n    children = [\n      App.Repo\n    ]\n  end\nend\n"
  }

  # One addition per bucket, so a classifier that collapses two of them fails.
  @meta_pair_additions %{
    # new file -> :sole_owner
    "lib/app/cache.ex" => "defmodule App.Cache do\nend\n",
    # top-level block appended -> :contributes
    "config/config.exs" =>
      "import Config\n\nconfig :app, key: :value\n\nconfig :app, App.Cache, adapter: Nebulex\n",
    # insertion inside a list literal -> :manual
    "lib/app/application.ex" =>
      "defmodule App.Application do\n  def start(_, _) do\n    children = [\n      App.Repo,\n      App.Cache\n    ]\n  end\nend\n",
    # added dep -> deps:
    "mix.exs" =>
      "defmodule App.MixProject do\n  defp deps do\n    [\n      {:jason, \"~> 1.4\"},\n      {:nebulex, \"~> 2.6\"}\n    ]\n  end\nend\n"
  }

  # A DIFFERENT project name from the :additions pair, and deliberately one that
  # does not collide with a filename: Template.capture/2 matches on segment
  # boundaries, so an app called "app" would placehold `app.css` into `APP.css`
  # and obscure every assertion about the path.
  @meta_pair_mix_exs "defmodule Myapp.MixProject do\n  def project do\n    [app: :myapp]\n  end\n\n  defp deps do\n    [\n      {:jason, \"~> 1.4\"}\n    ]\n  end\nend\n"

  # The measured defect: phx.new's daisyUI stylesheet, REWRITTEN by the Svelte
  # layer rather than appended to. Non-Elixir, so Classify sends it to
  # :contributes, and apply appended — leaving @plugin "daisyui" in place beside
  # a second @import.
  @meta_pair_rewrite_baseline %{
    "mix.exs" => @meta_pair_mix_exs,
    "assets/css/app.css" =>
      "@import \"tailwindcss\" source(none);\n@source \"../css\";\n@plugin \"daisyui\";\n"
  }

  @meta_pair_rewrite %{
    "assets/css/app.css" =>
      "@import \"tailwindcss\" source(none);\n@source \"../css\";\n@source \"../svelte/**/*.svelte\";\n"
  }

  # Two deletion shapes in one pair. config.exs deletes with unchanged text
  # behind it; README.md deletes to the very end of the diff, which only happens
  # when the file has no trailing newline and is the one shape that reaches the
  # flush AFTER the reduce.
  @meta_pair_deleting_baseline %{
    "mix.exs" => @meta_pair_mix_exs,
    "config/config.exs" =>
      "import Config\n\nconfig :myapp, key: :value\nconfig :myapp, legacy: true\n",
    "README.md" => "# Myapp\nlegacy"
  }

  @meta_pair_deleting %{
    "config/config.exs" => "import Config\n\nconfig :myapp, key: :value\n",
    "README.md" => "# Myapp"
  }

  # A meta project whose mix.exs adds an ALIAS rather than a dependency — the
  # shape the Svelte layer needs, and the one nothing captured before
  # Capstone.Plugin.MixChanges widened.
  @meta_pair_aliasing_baseline %{
    "mix.exs" =>
      "defmodule Myapp.MixProject do\n  def project do\n    [app: :myapp, deps: deps()]\n  end\n\n  defp deps, do: []\nend\n"
  }

  @meta_pair_aliasing %{
    "mix.exs" =>
      "defmodule Myapp.MixProject do\n  def project do\n    [app: :myapp, deps: deps(), aliases: aliases()]\n  end\n\n  defp deps, do: []\n\n  defp aliases do\n    [\n      \"assets.build\": [\"cmd --cd assets pnpm build\"]\n    ]\n  end\nend\n"
  }

  @default_meta_pair_variety :additions

  @doc """
  A throwaway baseline tree and a meta project built on it.

    * `:additions` — one change per bucket. The default.
    * `:rewrite` — a non-Elixir file whose content is REPLACED rather than
      appended to, which is the shape that classified as `:contributes`.
    * `:deleting` — one deletion with unchanged text behind it, and one running
      to the end of the file.
    * `:aliasing` — a meta project whose `mix.exs` adds an alias, not a dep.
    * `:supervised` — one added supervision child and nothing else.
    * `:supervised_multi` — three added supervision children and nothing else.
    * `:supervised_and_strategy` — that, plus a change the guard must catch.
    * `:configuring` — a contribution sitting above `config.exs`'s import.
    * `:configuring_runtime` — one inside `runtime.exs`'s production guard.
    * `:configuring_unplaceable` — one in the middle, which no rule reproduces.
    * `:whole_file` — a baseline file the meta project does not have at all.
  """
  @spec meta_pair_factory() :: %{baseline: Path.t(), meta: Path.t()}
  def meta_pair_factory, do: meta_pair(@default_meta_pair_variety)

  @spec meta_pair_factory(map()) :: %{baseline: Path.t(), meta: Path.t()}
  def meta_pair_factory(%{variety: variety}), do: meta_pair(variety)

  def meta_pair_factory(attrs) when map_size(attrs) == 0,
    do: meta_pair(@default_meta_pair_variety)

  defp meta_pair(variety) do
    {baseline_files, meta_files} = meta_pair_files(variety)
    root = Path.join(System.tmp_dir!(), "meta-pair-#{System.unique_integer([:positive])}")
    baseline = Path.join(root, "baseline")
    meta = Path.join(root, "meta")

    write_tree(baseline, baseline_files)
    write_tree(meta, meta_files)

    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(root) end)

    %{baseline: baseline, meta: meta}
  end

  defp meta_pair_files(:additions),
    do: {@meta_pair_baseline, Map.merge(@meta_pair_baseline, @meta_pair_additions)}

  defp meta_pair_files(:rewrite),
    do: {@meta_pair_rewrite_baseline, Map.merge(@meta_pair_rewrite_baseline, @meta_pair_rewrite)}

  defp meta_pair_files(:deleting),
    do:
      {@meta_pair_deleting_baseline, Map.merge(@meta_pair_deleting_baseline, @meta_pair_deleting)}

  # The meta project simply does not have the file. Whole-file removal is what
  # `Derive.run/1`'s :unrepresentable_deletions guard still refuses.
  # A meta project whose config.exs contribution sits ABOVE import_config —
  # the placement derive must observe rather than guess.
  defp meta_pair_files(:configuring),
    do:
      {%{
         "mix.exs" => "defmodule Myapp.MixProject do\n  def project, do: [app: :myapp]\nend\n",
         "config/config.exs" =>
           "import Config\n\nconfig :myapp, key: :value\n\n# This must remain at the bottom.\nimport_config \"\#{config_env()}.exs\"\n"
       },
       %{
         "mix.exs" => "defmodule Myapp.MixProject do\n  def project, do: [app: :myapp]\nend\n",
         "config/config.exs" =>
           "import Config\n\nconfig :myapp, key: :value\n\nconfig :live_svelte, ssr: false\n\n# This must remain at the bottom.\nimport_config \"\#{config_env()}.exs\"\n"
       }}

  # A contribution inside runtime.exs's production guard — the placement that
  # must NOT be recorded as an append, or it applies in every environment.
  defp meta_pair_files(:configuring_runtime),
    do:
      {%{
         "mix.exs" => "defmodule Myapp.MixProject do\n  def project, do: [app: :myapp]\nend\n",
         "config/runtime.exs" =>
           "import Config\n\nif config_env() == :prod do\n  config :myapp, secret: 1\nend\n"
       },
       %{
         "mix.exs" => "defmodule Myapp.MixProject do\n  def project, do: [app: :myapp]\nend\n",
         "config/runtime.exs" =>
           "import Config\n\nif config_env() == :prod do\n  config :myapp, secret: 1\n\n  config :myapp, extra: 2\nend\n"
       }}

  # A contribution in the MIDDLE of a config file, which no placement rule
  # reproduces — so it must fall through to :manual rather than be appended.
  defp meta_pair_files(:configuring_unplaceable),
    do:
      {%{
         "mix.exs" => "defmodule Myapp.MixProject do\n  def project, do: [app: :myapp]\nend\n",
         "config/config.exs" => "import Config\n\nconfig :myapp, a: 1\n\nconfig :myapp, b: 2\n"
       },
       %{
         "mix.exs" => "defmodule Myapp.MixProject do\n  def project, do: [app: :myapp]\nend\n",
         "config/config.exs" =>
           "import Config\n\nconfig :myapp, a: 1\n\nconfig :myapp, middle: true\n\nconfig :myapp, b: 2\n"
       }}

  # A meta project whose only change is one added supervision child — the
  # shape that currently produces a conflict region on every install.
  defp meta_pair_files(:supervised),
    do:
      {%{
         "mix.exs" => "defmodule Myapp.MixProject do\n  def project, do: [app: :myapp]\nend\n",
         "lib/myapp/application.ex" =>
           "defmodule Myapp.Application do\n  use Application\n\n  def start(_type, _args) do\n    children = [\n      Myapp.Repo\n    ]\n\n    Supervisor.start_link(children, strategy: :one_for_one)\n  end\nend\n"
       },
       %{
         "mix.exs" => "defmodule Myapp.MixProject do\n  def project, do: [app: :myapp]\nend\n",
         "lib/myapp/application.ex" =>
           "defmodule Myapp.Application do\n  use Application\n\n  def start(_type, _args) do\n    children = [\n      Myapp.Repo,\n      Myapp.Cache\n    ]\n\n    Supervisor.start_link(children, strategy: :one_for_one)\n  end\nend\n"
       }}

  # A meta project whose only change is THREE added supervision children — the
  # shape the :cqrs plugin's application.ex edit produces, which the N-child
  # auto-detection must also recognise, not just the one-child case above.
  defp meta_pair_files(:supervised_multi),
    do:
      {%{
         "mix.exs" => "defmodule Myapp.MixProject do\n  def project, do: [app: :myapp]\nend\n",
         "lib/myapp/application.ex" =>
           "defmodule Myapp.Application do\n  use Application\n\n  def start(_type, _args) do\n    children = [\n      Myapp.Repo\n    ]\n\n    Supervisor.start_link(children, strategy: :one_for_one)\n  end\nend\n"
       },
       %{
         "mix.exs" => "defmodule Myapp.MixProject do\n  def project, do: [app: :myapp]\nend\n",
         "lib/myapp/application.ex" =>
           "defmodule Myapp.Application do\n  use Application\n\n  def start(_type, _args) do\n    children = [\n      Myapp.Repo,\n      Myapp.Cache,\n      Myapp.Worker,\n      Myapp.Scheduler\n    ]\n\n    Supervisor.start_link(children, strategy: :one_for_one)\n  end\nend\n"
       }}

  # The same, plus a change beyond the children list. The guard must still
  # fire here: only the shape with a deterministic answer stops being manual.
  defp meta_pair_files(:supervised_and_strategy),
    do:
      {%{
         "mix.exs" => "defmodule Myapp.MixProject do\n  def project, do: [app: :myapp]\nend\n",
         "lib/myapp/application.ex" =>
           "defmodule Myapp.Application do\n  use Application\n\n  def start(_type, _args) do\n    children = [\n      Myapp.Repo\n    ]\n\n    Supervisor.start_link(children, strategy: :one_for_one)\n  end\nend\n"
       },
       %{
         "mix.exs" => "defmodule Myapp.MixProject do\n  def project, do: [app: :myapp]\nend\n",
         "lib/myapp/application.ex" =>
           "defmodule Myapp.Application do\n  use Application\n\n  def start(_type, _args) do\n    children = [\n      Myapp.Repo,\n      Myapp.Cache\n    ]\n\n    Supervisor.start_link(children, strategy: :one_for_all)\n  end\nend\n"
       }}

  defp meta_pair_files(:aliasing),
    do: {@meta_pair_aliasing_baseline, @meta_pair_aliasing}

  defp meta_pair_files(:whole_file),
    do:
      {@meta_pair_rewrite_baseline, Map.drop(@meta_pair_rewrite_baseline, ["assets/css/app.css"])}

  defp write_tree(dir, files) do
    Enum.each(files, fn {relative, contents} ->
      file = Path.join(dir, relative)
      File.mkdir_p!(Path.dirname(file))
      File.write!(file, contents)
    end)
  end

  # --- ported from capstone_umbrella/apps/capstone, Phase 1 subset ----------
  # Only the factories Phase 1's tests (Clock, Hash, Root, Template, Source,
  # BoundaryGuard) reach for. Manifest/Plugin-shaped factories and the
  # umbrella's own Capstone.Config-shape factories (config_map, v2/v3
  # sections, meta_pair) are NOT ported: this package kept its own, differently
  # shaped Capstone.Config (Literal/Project/Security/Container/Fields) rather
  # than the umbrella's 14-module schema, so nothing here should generate
  # fixtures for a schema this package does not have.

  @default_banned_token "File.cd"
  @default_exs_term_shape :two_keys
  @default_exs_source_shape :empty
  @default_unparseable_variety :token_missing

  # The .ex fixture every hashing property is measured against. Two-space
  # indentation the reindent test can widen; a moduledoc, an atom and an integer
  # literal for the change varieties to perturb; and no double space inside any
  # literal, so a global "  " -> "      " replace can only touch indentation.
  @elixir_source """
  defmodule Fixture do
    @moduledoc "A fixture module."

    def add(left) do
      total = left + 1
      {:ok, total}
    end
  end
  """

  # Both forms `Code.string_to_quoted!/2` warns about at 1.20.3 — a
  # single-quoted charlist and a needlessly quoted atom. ~S so neither survives
  # into the fixture pre-interpreted.
  @legacy_elixir_source ~S"""
  defmodule Legacy do
    def name, do: {'legacy', :"quoted"}
  end
  """

  # The three parser failures the hash surfaces are exactly the three malformed
  # shapes the .exs decode corpus already carries — keyed there by the delimiter
  # at fault, and here by the exception `Code.string_to_quoted!/2` raises for it.
  @unparseable_shapes %{
    token_missing: :unclosed_delimiter,
    mismatched_delimiter: :mismatched_delimiter,
    syntax_error: :stray_delimiter
  }

  @doc "An .ex source embedding a banned token, for the not-vacuous guard test."
  @spec banned_token_source_factory() :: %{source: String.t(), token: String.t()}
  def banned_token_source_factory, do: token_source(@default_banned_token)

  # ExMachina prefers the arity-1 factory whenever one is exported, so this
  # clause — not the arity-0 above — is what `build(:banned_token_source)` runs.
  # The `map_size/1` guard keeps an unknown attribute a FunctionClauseError
  # instead of a silently ignored one.
  @doc "The same source, built around a caller-supplied banned token."
  @spec banned_token_source_factory(map()) :: %{source: String.t(), token: String.t()}
  def banned_token_source_factory(%{token: token}), do: token_source(token)

  def banned_token_source_factory(attrs) when map_size(attrs) == 0,
    do: token_source(@default_banned_token)

  @doc """
  A `plugin.exs`-shaped manifest term — the CODEC round-trip corpus.

  A plain map, not a struct: this exercises `Capstone.Source`'s generic .exs
  codec against a realistic shape, without depending on `Capstone.Manifest`.
  """
  @spec fireside_manifest_factory() :: map()
  def fireside_manifest_factory do
    %{
      base: :web,
      schema_version: 1,
      capstone_version: "1.0.0",
      generated_at: @default_timestamp,
      config_digest: digest("a"),
      plugins: [
        %{
          name: :valkey,
          version: "1.3.0",
          origin: {:hex, "capstone_valkey", "1.3.0"},
          applied_at: @default_timestamp,
          files: [
            %{path: "lib/my_app/cache.ex", mode: :sole_owner, hash: digest("b")},
            %{
              path: "compose.yaml",
              mode: :contributes,
              key: :valkey_service,
              hash: digest("c")
            }
          ]
        }
      ]
    }
  end

  @doc "A plain-data term shaped to exercise one encoder property."
  @spec exs_term_factory() :: map()
  def exs_term_factory, do: exs_term(@default_exs_term_shape)

  @doc "The same term, for a caller-named shape."
  @spec exs_term_factory(map()) :: map()
  def exs_term_factory(%{shape: shape}), do: exs_term(shape)

  def exs_term_factory(attrs) when map_size(attrs) == 0, do: exs_term(@default_exs_term_shape)

  @doc "Terms holding a value `inspect/2` renders as `#Name<...>` — a comment in .exs."
  @spec unencodable_exs_terms_factory() :: %{terms: [map()]}
  def unencodable_exs_terms_factory do
    %{
      terms:
        Enum.map([self(), make_ref(), &Enum.map/2, ~D[2026-08-11], MapSet.new([1])], &%{a: &1})
    }
  end

  @doc "`.exs` source for a named decode scenario."
  @spec exs_source_factory() :: %{shape: atom(), source: String.t()}
  def exs_source_factory, do: exs_source(@default_exs_source_shape)

  @doc "The same source, for a caller-named shape."
  @spec exs_source_factory(map()) :: %{shape: atom(), source: String.t()}
  def exs_source_factory(%{shape: shape}), do: exs_source(shape)

  def exs_source_factory(attrs) when map_size(attrs) == 0,
    do: exs_source(@default_exs_source_shape)

  @doc "Source that would write a canary file and define a module if it were evaluated."
  @spec code_executing_exs_source_factory() :: %{
          canary: Path.t(),
          module: module(),
          source: String.t()
        }
  def code_executing_exs_source_factory do
    canary = Path.join(System.tmp_dir!(), "canary-#{System.unique_integer([:positive])}")

    source = """
    File.write!("#{canary}", "pwned")

    defmodule PollutedByManifest do
      def hi, do: :yes
    end

    %{a: 1}
    """

    %{canary: canary, module: PollutedByManifest, source: source}
  end

  @doc "A parseable .ex source — the hashing corpus."
  @spec elixir_source_factory() :: %{variety: atom(), source: String.t()}
  def elixir_source_factory, do: elixir_source(@default_elixir_source_variety)

  @doc "The same source, for a caller-named variety."
  @spec elixir_source_factory(map()) :: %{variety: atom(), source: String.t()}
  def elixir_source_factory(%{variety: variety}), do: elixir_source(variety)

  def elixir_source_factory(attrs) when map_size(attrs) == 0,
    do: elixir_source(@default_elixir_source_variety)

  @doc "An .ex source that fails to parse, named for the exception it raises."
  @spec unparseable_source_factory() :: %{variety: atom(), source: String.t()}
  def unparseable_source_factory, do: unparseable_source(@default_unparseable_variety)

  @doc "The same source, for a caller-named parser failure."
  @spec unparseable_source_factory(map()) :: %{variety: atom(), source: String.t()}
  def unparseable_source_factory(%{variety: variety}), do: unparseable_source(variety)

  def unparseable_source_factory(attrs) when map_size(attrs) == 0,
    do: unparseable_source(@default_unparseable_variety)

  # The shapes `mix` accepts for a deps list. Three of them defeated the regex
  # in Apply.insert/2 and two defeated the reader in Deps.declarations/1, each
  # reporting success on the shapes it could not handle — so every one of them
  # is a fixture rather than a comment.
  @mix_exs_shapes %{
    defp_do:
      "defmodule T.MixProject do\n  def project, do: [app: :t, deps: deps()]\n\n  defp deps do\n    [\n      {:jason, \"~> 1.4\"}\n    ]\n  end\nend\n",
    def_do:
      "defmodule T.MixProject do\n  def project, do: [app: :t, deps: deps()]\n\n  def deps do\n    [\n      {:jason, \"~> 1.4\"}\n    ]\n  end\nend\n",
    defp_keyword:
      "defmodule T.MixProject do\n  def project, do: [app: :t, deps: deps()]\n\n  defp deps, do: [{:jason, \"~> 1.4\"}]\nend\n",
    inline:
      "defmodule T.MixProject do\n  def project, do: [app: :t, deps: [{:jason, \"~> 1.4\"}]]\nend\n",
    # Located, and refused: the list is computed, so there is no literal to
    # splice into and guessing is what Capstone.Source.MixExs exists to stop.
    computed:
      "defmodule T.MixProject do\n  def project, do: [app: :t, deps: deps()]\n\n  defp deps, do: base() ++ extra()\nend\n",
    no_deps: "defmodule T.MixProject do\n  def project, do: [app: :t]\nend\n",
    # Parses, and has no body to read. Not valid on its own to `mix`, but this
    # module PARSES rather than compiles, so it must refuse it by name instead
    # of crashing on a clause that does not match.
    bodiless_deps:
      "defmodule T.MixProject do\n  def project, do: [app: :t]\n\n  defp deps\nend\n",
    # project/0 delegating to a helper: located, and not a literal to patch.
    computed_project: "defmodule T.MixProject do\n  def project, do: config()\nend\n",
    # An alias declared as a bare command rather than a list. `mix` accepts it.
    scalar_alias:
      "defmodule T.MixProject do\n  def project, do: [app: :t, aliases: aliases()]\n\n  defp aliases, do: [setup: \"deps.get\"]\nend\n",
    with_aliases:
      "defmodule T.MixProject do\n  def project, do: [app: :t, deps: deps(), aliases: aliases()]\n\n  defp deps, do: []\n\n  defp aliases do\n    [\n      setup: [\"deps.get\"]\n    ]\n  end\nend\n",
    # `mix new` writes no aliases/0 at all — the ordinary case on an :otp
    # project, and the one the Svelte layer hits on every install.
    without_aliases:
      "defmodule T.MixProject do\n  def project, do: [app: :t, deps: deps()]\n\n  defp deps, do: []\nend\n"
  }

  @default_mix_exs_shape :defp_do

  # The shapes that decide WHERE a contribution goes. phx.new's config.exs ends
  # with import_config and carries a comment saying it must stay there "so it
  # overrides the configuration defined above"; dev/test/prod never have one;
  # runtime.exs puts its production settings inside a config_env() guard.
  @config_shapes %{
    with_import:
      "import Config\n\nconfig :t, key: :value\n\n# Import environment specific config. This must remain at the bottom\n# of this file so it overrides the configuration defined above.\nimport_config \"\#{config_env()}.exs\"\n",
    without_import: "import Config\n\nconfig :t, key: :value\n",
    with_env_guard:
      "import Config\n\nif config_env() == :prod do\n  config :t, secret: System.get_env(\"SECRET\")\nend\n",
    with_repo:
      "import Config\n\nconfig :t, T.Repo,\n  username: \"postgres\",\n  password: \"postgres\",\n  hostname: \"localhost\"\n"
  }

  @default_config_shape :with_import

  # What `mix new --sup` and `phx.new` both produce, plus the two shapes that
  # must degrade to the existing loud path rather than be guessed at.
  @application_shapes %{
    literal:
      "defmodule T.Application do\n  use Application\n\n  @impl true\n  def start(_type, _args) do\n    children = [\n      T.Repo,\n      TWeb.Endpoint\n    ]\n\n    Supervisor.start_link(children, strategy: :one_for_one)\n  end\nend\n",
    computed:
      "defmodule T.Application do\n  use Application\n\n  @impl true\n  def start(_type, _args) do\n    children = base_children() ++ extra_children()\n\n    Supervisor.start_link(children, strategy: :one_for_one)\n  end\nend\n",
    empty:
      "defmodule T.Application do\n  use Application\n\n  @impl true\n  def start(_type, _args) do\n    children = []\n\n    Supervisor.start_link(children, strategy: :one_for_one)\n  end\nend\n",
    # start/2 exists and the binding is called something else. Located by NAME
    # rather than by "the first list in the function": matching any list would
    # place a child into whichever literal came first.
    renamed:
      "defmodule T.Application do\n  use Application\n\n  @impl true\n  def start(_type, _args) do\n    tree = [\n      T.Repo\n    ]\n\n    Supervisor.start_link(tree, strategy: :one_for_one)\n  end\nend\n",
    no_start: "defmodule T.Application do\n  use Application\nend\n"
  }

  @default_application_shape :literal

  @doc "A `mix.exs` source in one of the shapes `mix` accepts."
  @spec mix_exs_shape_factory() :: %{shape: atom(), source: String.t()}
  def mix_exs_shape_factory, do: mix_exs_shape(@default_mix_exs_shape)

  @doc "The same source, in a caller-named shape."
  @spec mix_exs_shape_factory(map()) :: %{shape: atom(), source: String.t()}
  def mix_exs_shape_factory(%{shape: shape}), do: mix_exs_shape(shape)

  def mix_exs_shape_factory(attrs) when map_size(attrs) == 0,
    do: mix_exs_shape(@default_mix_exs_shape)

  defp mix_exs_shape(shape), do: %{shape: shape, source: Map.fetch!(@mix_exs_shapes, shape)}

  @doc "A `config/*.exs` source in one of the shapes the generators produce."
  @spec config_shape_factory() :: %{shape: atom(), source: String.t()}
  def config_shape_factory, do: config_shape(@default_config_shape)

  @doc "The same source, in a caller-named shape."
  @spec config_shape_factory(map()) :: %{shape: atom(), source: String.t()}
  def config_shape_factory(%{shape: shape}), do: config_shape(shape)

  def config_shape_factory(attrs) when map_size(attrs) == 0,
    do: config_shape(@default_config_shape)

  defp config_shape(shape), do: %{shape: shape, source: Map.fetch!(@config_shapes, shape)}

  @doc "A `lib/APP/application.ex` source in one of the shapes the generators produce."
  @spec application_shape_factory() :: %{shape: atom(), source: String.t()}
  def application_shape_factory, do: application_shape(@default_application_shape)

  @doc "The same source, in a caller-named shape."
  @spec application_shape_factory(map()) :: %{shape: atom(), source: String.t()}
  def application_shape_factory(%{shape: shape}), do: application_shape(shape)

  def application_shape_factory(attrs) when map_size(attrs) == 0,
    do: application_shape(@default_application_shape)

  defp application_shape(shape),
    do: %{shape: shape, source: Map.fetch!(@application_shapes, shape)}

  defp elixir_source(variety), do: %{variety: variety, source: elixir_source_text(variety)}

  defp elixir_source_text(:plain), do: @elixir_source
  defp elixir_source_text(:renamed_variable), do: String.replace(@elixir_source, "total", "sum")
  defp elixir_source_text(:changed_atom), do: String.replace(@elixir_source, ":ok", ":done")
  defp elixir_source_text(:legacy_charlist), do: @legacy_elixir_source

  defp elixir_source_text(:changed_literal),
    do: String.replace(@elixir_source, "left + 1", "left + 2")

  defp elixir_source_text(:changed_moduledoc),
    do: String.replace(@elixir_source, "A fixture", "Another fixture")

  defp elixir_source_text(:added_function),
    do: String.replace(@elixir_source, "\nend\n", "\n\n  def zero, do: 0\nend\n")

  # 39 keys, past the 32 at which a real map stops preserving insertion order:
  # the AST holds a keyword list, and normalise/2 must not round-trip it through
  # a map on the way to the digest.
  defp elixir_source_text(:wide_map_literal) do
    "%{" <> Enum.map_join(1..39, ", ", &"key_#{&1}: #{&1}") <> "}\n"
  end

  defp unparseable_source(variety) do
    %{variety: variety, source: source_for(Map.fetch!(@unparseable_shapes, variety))}
  end

  defp token_source(token) do
    %{token: token, source: "defmodule A do\n  def f, do: #{token}\nend\n"}
  end

  defp digest(byte), do: "sha256:" <> String.duplicate(byte, 64)

  defp exs_term(:two_keys), do: %{b: 2, a: 1}
  defp exs_term(:nested_unsorted), do: %{z: %{y: 1, a: 2}, a: 3}
  defp exs_term(:ordered_list), do: %{k: [:z, :a, :m], kw: [z: 1, a: 2]}
  defp exs_term(:long_path), do: %{path: String.duplicate("lib/very/long/path/", 8) <> "x.ex"}

  # Renders to 89 columns on one line — deliberately inside the 81..98 band
  # between the encoder's `width: 80` and the formatter's `line_length: 98`.
  # That band is the ONLY place `pretty: true` and `width: 80` are observable:
  # measured, 80 columns still fits on one line and 81 is the first that wraps,
  # while anything over 98 wraps under every setting. 89 clears both edges.
  defp exs_term(:eighty_one_to_ninety_eight_columns) do
    %{
      mode: :sole_owner,
      path: "lib/my_app/some/moderately/long/path" <> String.duplicate("x", 20) <> ".ex"
    }
  end

  defp exs_term(:bulky), do: %{list: Enum.to_list(1..250), text: String.duplicate("x", 5000)}

  defp exs_source(shape), do: %{shape: shape, source: source_for(shape)}

  defp source_for(:empty), do: ""
  defp source_for(:comment_only), do: "# just a comment\n"
  defp source_for(:two_maps), do: "%{a: 1}\n%{b: 2}\n"
  defp source_for(:keyword_list), do: "[a: 1]"
  defp source_for(:bare_string), do: ~s|"hello"|
  defp source_for(:nil_root), do: "nil"
  defp source_for(:unary_minus), do: "%{a: -1}"
  defp source_for(:module_alias), do: "%{module: MyApp}"
  defp source_for(:unquote_splicing), do: "unquote_splicing([%{a: 1}])"
  defp source_for(:unclosed_delimiter), do: "%{a: 1"
  defp source_for(:mismatched_delimiter), do: "%{a: 1]"
  defp source_for(:stray_delimiter), do: "%{a: 1, }}"

  # ~S, not ~s: the interpolation must survive into the .exs source unevaluated.
  # With ~s the fixture would arrive at the decoder as the literal `%{a: "x2y"}`
  # and the test asserting a raise would fail.
  defp source_for(:interpolated_string), do: ~S|%{a: "x#{1 + 1}y"}|
end
