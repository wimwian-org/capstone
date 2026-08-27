defmodule Capstone.Source.ConfigExs do
  @moduledoc """
  Places a contribution inside a `config/*.exs`, by that file's own rules.

  A config file is not an appendable file. Every `mix phx.new` project ends
  `config/config.exs` with `import_config "\#{config_env()}.exs"` under a
  comment saying it must stay there *"so it overrides the configuration defined
  above"* — so a block appended past it outranks the project's own `dev.exs`,
  `test.exs` and `prod.exs`. Measured on `priv/meta/baseline_api`: the
  contribution landed at line 45 with the import at line 43, and silently won.

  Source text in, source text out, no filesystem — the shape
  `Capstone.Source.MixExs` established, over the same `Sourceror.get_range/1` +
  `patch_string/2` engine. `Sourceror.to_string/1` is never called: reprinting
  a file the project owns is a first-order R6 violation.

  Not to be confused with `Capstone.Config`, which reads `target.exs` — a
  different file describing a different thing. The collision is legible rather
  than dangerous, and is left unresolved deliberately.
  """

  alias Capstone.Vendor.Sourceror

  alias Capstone.Vendor.Sourceror.Patch
  alias Capstone.Vendor.Sourceror.Zipper

  @type error ::
          {:no_env_guard, atom()}
          | {:no_statement, [atom() | module()]}
          | {:no_key, atom()}
          | {:unparseable, term()}

  @doc """
  Splices `block` above `source`'s `import_config` call.

  Above its LEADING COMMENTS, not merely above the call: the comment phx.new
  writes there explains why the import is last, and splicing between the two
  would separate a comment from the statement it describes.

  A file with no `import_config` — every `dev.exs`, `test.exs`, `prod.exs` and
  every `mix new` config — appends instead, which is correct there because
  nothing follows that the block could override.

  Idempotent by substring, as `:contributes` has always been: where the block
  sits does not change whether it is already present.

  The SPLICE owns the separation, not the block: whatever trailing newlines the
  block carries, exactly one blank line follows it. A block reconstructed from
  hunk lines and one shipped as a literal suffix differ in that trailing
  whitespace, and derive replays this function to decide where a contribution
  was observed — so the two must produce identical bytes or that replay reports
  a false negative.
  """
  @spec insert_before_import(binary(), binary()) :: {:ok, binary()} | {:error, error()}
  def insert_before_import(source, block) do
    with {:ok, quoted} <- parse(source) do
      cond do
        String.contains?(source, block) -> {:ok, source}
        node = find(quoted, &import_config?/1) -> {:ok, splice_above(source, node, block)}
        true -> {:ok, source <> block}
      end
    end
  end

  @doc """
  Splices `block` inside `source`'s `if config_env() == env do` guard.

  A file with no guard for that environment returns
  `{:error, {:no_env_guard, env}}` and writes nothing. It does NOT fall back to
  appending, which `insert_before_import/2` does and which is correct there:
  appending here would put a production-only setting outside the guard and make
  it a default in every environment, secrets included.
  """
  @spec insert_in_env(binary(), atom(), binary()) :: {:ok, binary()} | {:error, error()}
  def insert_in_env(source, env, block) do
    with {:ok, quoted} <- parse(source) do
      cond do
        String.contains?(source, block) -> {:ok, source}
        node = find(quoted, &env_guard?(&1, env)) -> {:ok, splice_inside(source, node, block)}
        true -> {:error, {:no_env_guard, env}}
      end
    end
  end

  @doc """
  Replaces `key` inside the `config` statement addressed by `path`.

  `path` is the statement's leading arguments — `[:app]` for
  `config :app, key: value`, `[:app, App.Repo]` for
  `config :app, App.Repo, key: value`. `value` is SOURCE TEXT, as
  `Capstone.Source.MixExs.put_project_key/3`'s is.

  An absent statement or an absent key is an error, never an insert. "Override
  this value" and "introduce this key" are different intentions, and conflating
  them is how a typo becomes a new config key nobody reads.

  This is the "replacement at a matched site" shape §4 of the deletion spec
  named — the key survives and its value changes — and it is the reason those
  cases need not become a conflict region a human resolves on every install.
  """
  @spec put_key(binary(), [atom() | module()], atom(), binary()) ::
          {:ok, binary()} | {:error, error()}
  def put_key(source, path, key, value) do
    with {:ok, quoted} <- parse(source),
         {:ok, settings} <- statement(quoted, path),
         {:ok, current} <- pair_value(settings, key) do
      {:ok, replace(source, current, value)}
    end
  end

  defp statement(quoted, path) do
    case find(quoted, &config_statement?(&1, path)) do
      nil -> {:error, {:no_statement, path}}
      {:config, _meta, args} -> {:ok, List.last(args)}
    end
  end

  defp config_statement?({:config, _meta, args}, path) when length(args) == length(path) + 1,
    do: args |> Enum.drop(-1) |> Enum.map(&literal/1) == path

  defp config_statement?(_node, _path), do: false

  defp literal({:__block__, _meta, [value]}), do: value
  defp literal({:__aliases__, _meta, segments}), do: Module.concat(segments)
  defp literal(other), do: other

  defp pair_value(settings, key) when is_list(settings) do
    case Enum.find(settings, fn {name, _value} -> literal(name) == key end) do
      nil -> {:error, {:no_key, key}}
      {_name, value} -> {:ok, value}
    end
  end

  # A settings argument that is not a keyword list — `config :app, :key, value`
  # addresses a single setting rather than a block of them, and there is no
  # `key` in it to replace.
  defp pair_value(_settings, key), do: {:error, {:no_key, key}}

  defp replace(source, current, value) do
    if Macro.to_string(current) == value do
      source
    else
      Sourceror.patch_string(source, [
        %Patch{range: Sourceror.get_range(current), change: value}
      ])
    end
  end

  defp parse(source) do
    {:ok, Sourceror.parse_string!(source)}
  rescue
    error -> {:error, {:unparseable, error}}
  end

  defp find(quoted, predicate) do
    quoted |> Zipper.zip() |> Zipper.find(predicate) |> node_of()
  end

  defp node_of(nil), do: nil
  defp node_of(zipper), do: Zipper.node(zipper)

  defp import_config?({:import_config, _meta, _args}), do: true
  defp import_config?(_node), do: false

  defp splice_above(source, {_call, meta, _args} = node, block) do
    line = first_line(meta, node)
    point = [line: line, column: 1]

    Sourceror.patch_string(source, [
      %Patch{
        range: %Sourceror.Range{start: point, end: point},
        change: String.trim_trailing(block, "\n") <> "\n\n",
        preserve_indentation: false
      }
    ])
  end

  defp env_guard?({:if, _meta, [condition, [{{:__block__, _, [:do]}, _body}]]}, env),
    do: env_condition?(condition, env)

  defp env_guard?(_node, _env), do: false

  # `config_env() == :prod` and nothing looser. A guard for a DIFFERENT
  # environment is not a match: putting a :prod block inside an `if
  # config_env() == :dev` is the same failure as putting it outside any guard.
  defp env_condition?({:==, _meta, [{:config_env, _, _}, {:__block__, _, [env]}]}, env), do: true
  defp env_condition?(_condition, _env), do: false

  # Spliced after the guard's LAST expression rather than at its `end`: the
  # `end` line is the block's, and inserting at it would put the statement
  # outside on a file whose formatting differs from phx.new's.
  defp splice_inside(source, {:if, _meta, [_condition, [{_do, body}]]}, block) do
    range = body |> last_expression() |> Sourceror.get_range()
    point = [line: range.end[:line], column: range.end[:column]]
    margin = String.duplicate(" ", range.start[:column] - 1)

    Sourceror.patch_string(source, [
      %Patch{
        range: %Sourceror.Range{start: point, end: point},
        change: "\n\n" <> indent(dedent(block), margin),
        # Indented here rather than by Capstone.Vendor.Sourceror: `preserve_indentation: true`
        # indents BLANK lines too, leaving trailing whitespace that the meta
        # file does not have and that derive's byte-exact replay would reject.
        preserve_indentation: false
      }
    ])
  end

  defp indent(block, margin) do
    block
    |> String.split("\n")
    |> Enum.map_join("\n", fn
      "" -> ""
      line -> margin <> line
    end)
  end

  defp last_expression({:__block__, _meta, expressions}) when expressions != [],
    do: List.last(expressions)

  defp last_expression(only), do: only

  # The SPLICE owns the indentation, not the block. `preserve_indentation: true`
  # re-indents every line after the first to the guard's level, so a block that
  # already carries that indentation gets it twice — and a block reconstructed
  # from hunk lines carries the meta file's blank lines at either end. Both are
  # stripped here so derive's replay and apply produce identical bytes.
  defp dedent(block) do
    lines =
      block
      |> String.split("\n")
      |> Enum.drop_while(&(String.trim(&1) == ""))
      |> Enum.reverse()
      |> Enum.drop_while(&(String.trim(&1) == ""))
      |> Enum.reverse()

    margin =
      lines
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.map(&(String.length(&1) - String.length(String.trim_leading(&1))))
      |> Enum.min(fn -> 0 end)

    Enum.map_join(lines, "\n", &String.slice(&1, margin..-1//1))
  end

  # A node's own range starts at the call, so a file whose import carries a
  # comment block needs the comment's line instead.
  defp first_line(meta, node) do
    case Keyword.get(meta, :leading_comments, []) do
      [] -> Sourceror.get_range(node).start[:line]
      comments -> comments |> Enum.map(& &1.line) |> Enum.min()
    end
  end
end

defmodule Capstone.Source.ConfigExs.Error do
  @moduledoc """
  Raised when a `config/*.exs` site a plugin must contribute to cannot be
  located.

  A contribution that names an environment guard the target does not have must
  fail at install time: appending it instead is how a production-only secret
  becomes a test default.
  """
  defexception [:message]
end
