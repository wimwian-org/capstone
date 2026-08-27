defmodule Capstone.Source.MixExs do
  @moduledoc """
  Locates and patches constructs in a `mix.exs`, structurally (SDD R5, R6).

  The one module that knows what a `mix.exs` looks like. Reading and writing
  live together deliberately: they were separate and they disagreed — the
  writer matched one of the four shapes `mix` accepts, the reader matched two,
  and each reported success on the shapes it could not handle.

  Every function takes and returns SOURCE TEXT and touches no filesystem, so a
  caller supplies bytes from wherever it has them and this module is coverable
  without generating a project.

  Placement is `Sourceror.get_range/1` followed by `Sourceror.patch_string/2`,
  which splices at a range and copies every other byte through unchanged.
  `Sourceror.to_string/1` is never called here: reprinting a file the project
  owns is a first-order R6 violation, and `mix.exs`'s own comment records the
  measurement that rejected it.
  """

  alias Capstone.Vendor.Sourceror
  alias Capstone.Vendor.Sourceror.Patch
  alias Capstone.Vendor.Sourceror.Zipper

  @type error ::
          {:no_deps_list, :not_found | :not_a_literal}
          | {:no_project_function, :not_found}
          | {:no_aliases, :not_found}
          | {:unparseable, term()}

  @doc """
  The dependency declarations in `source`, as the strings the author wrote.

  Source strings rather than terms, so the manifest records `only:` and
  `runtime:` exactly as written (D10).
  """
  @spec deps(binary()) :: {:ok, [binary()]} | {:error, error()}
  def deps(source) do
    with {:ok, quoted} <- parse(source),
         {:ok, list, _range} <- deps_list(quoted) do
      {:ok, Enum.map(list, &Macro.to_string/1)}
    end
  end

  @doc """
  Adds `dep` to `source`'s dependency list.

  Idempotent, decided by comparing PARSED declarations rather than text: a
  reflowed declaration is not an absent one, and duplicating it makes `mix`
  reject the file.

  The dependency lands at the TOP of the list, which `priv/meta/cache_component`
  records and the round trip compares byte for byte. A single-line list stays
  single-line and a multi-line one stays multi-line — `patch_string/2` indents
  continuation lines relative to the range start, so the change carries no
  leading whitespace of its own.
  """
  @spec add_dep(binary(), binary()) :: {:ok, binary()} | {:error, error()}
  def add_dep(source, dep) do
    with {:ok, quoted} <- parse(source),
         {:ok, list, range} <- deps_list(quoted) do
      if declared?(list, dep),
        do: {:ok, source},
        else: {:ok, prepend(source, list, range, dep)}
    end
  end

  @doc """
  The `project/0` keyword list in `source`, as `{key, source string}` pairs.

  Values are strings rather than terms for the same reason `deps/1`'s are: what
  the author wrote is what the manifest must record.
  """
  @spec project_keys(binary()) :: {:ok, keyword()} | {:error, error()}
  def project_keys(source) do
    with {:ok, quoted} <- parse(source),
         {:ok, list, _range} <- keyword_list(quoted, :project, {:no_project_function, :not_found}) do
      {:ok, to_pairs(list)}
    end
  end

  @doc """
  Sets `key` to `value` in `source`'s `project/0`.

  `value` is SOURCE TEXT, not a term — `"aliases()"` is a call and `":renamed"`
  an atom, and a plugin records what it wants written rather than a term
  this module would have to render back.
  """
  @spec put_project_key(binary(), atom(), binary()) :: {:ok, binary()} | {:error, error()}
  def put_project_key(source, key, value) do
    with {:ok, quoted} <- parse(source),
         {:ok, list, range} <- keyword_list(quoted, :project, {:no_project_function, :not_found}) do
      {:ok, put_pair(source, list, range, key, value)}
    end
  end

  @doc """
  The `aliases/0` keyword list in `source`, as `{name, [command source]}` pairs.

  `{:error, {:no_aliases, :not_found}}` when the project declares none, which
  every `mix new` project does.
  """
  @spec aliases(binary()) :: {:ok, keyword()} | {:error, error()}
  def aliases(source) do
    with {:ok, quoted} <- parse(source),
         {:ok, list, _range} <- keyword_list(quoted, :aliases, {:no_aliases, :not_found}) do
      {:ok, for({{:__block__, _km, [name]}, value} <- list, do: {name, commands(value)})}
    end
  end

  @doc """
  Sets `name` to `commands` in `source`'s `aliases/0`.

  Three cases, all of which the Svelte layer needs: the key is absent and is
  added; the key exists and its command list is REPLACED; `aliases/0` does not
  exist and is created, with `aliases: aliases()` wired into `project/0` — the
  ordinary case on a `mix new` project, where a function nothing calls would be
  inert, and silently so.

  Replacement is why idempotency is structural here: after one apply the old
  commands are gone, so a textual presence test cannot tell "already applied"
  from "never applied".
  """
  @spec put_alias(binary(), atom(), [binary()]) :: {:ok, binary()} | {:error, error()}
  def put_alias(source, name, commands) do
    case aliases(source) do
      {:ok, _existing} -> put_existing_alias(source, name, commands)
      {:error, {:no_aliases, :not_found}} -> create_aliases(source, name, commands)
      {:error, reason} -> {:error, reason}
    end
  end

  defp put_existing_alias(source, name, commands) do
    with {:ok, quoted} <- parse(source),
         {:ok, list, range} <- keyword_list(quoted, :aliases, {:no_aliases, :not_found}) do
      {:ok, put_pair(source, list, range, name, "[" <> Enum.join(commands, ", ") <> "]")}
    end
  end

  # The function AND the project/0 wiring, or the alias is inert: mix reads
  # aliases from project/0, so a defp nothing calls changes nothing.
  defp create_aliases(source, name, commands) do
    with {:ok, quoted} <- parse(source),
         {:ok, _list, _range} <-
           keyword_list(quoted, :project, {:no_project_function, :not_found}) do
      body = "[\n  #{key_source(name)} [#{Enum.join(commands, ", ")}]\n]"
      appended = append_function(source, quoted, "aliases", body)

      put_project_key(appended, :aliases, "aliases()")
    end
  end

  defp parse(source) do
    {:ok, Sourceror.parse_string!(source)}
  rescue
    error -> {:error, {:unparseable, error}}
  end

  # Two stages, and the order is load-bearing. `deps/0` is looked for FIRST,
  # because a project that delegates writes `deps: deps()` in project/0 and a
  # depth-first walk reaches that keyword pair before the function it names —
  # matching it would report the delegation as the list and refuse a perfectly
  # patchable file.
  defp deps_list(quoted) do
    case find(quoted, &deps_function?/1) do
      nil -> inline_deps(quoted)
      node -> literal(function_body(node))
    end
  end

  defp inline_deps(quoted) do
    case find(quoted, &inline_deps?/1) do
      nil -> {:error, {:no_deps_list, :not_found}}
      {_key, value} -> literal(value)
    end
  end

  defp find(quoted, predicate) do
    quoted |> Zipper.zip() |> Zipper.find(predicate) |> node_of()
  end

  defp node_of(nil), do: nil
  defp node_of(zipper), do: Zipper.node(zipper)

  defp deps_function?({def_, _meta, [{:deps, _, _} | _rest]}) when def_ in [:def, :defp], do: true
  defp deps_function?(_node), do: false

  # A `deps:` pair counts only when its value is a literal list. `deps: deps()`
  # is a delegation, not a declaration.
  defp inline_deps?({{:__block__, _meta, [:deps]}, value}),
    do: match?({:ok, _, _}, literal(value))

  defp inline_deps?(_node), do: false

  defp function_body({_def, _meta, [_head, [{{:__block__, _, [:do]}, body}]]}), do: body
  defp function_body(_node), do: nil

  # Capstone.Vendor.Sourceror wraps every literal in a `__block__` carrying its metadata, so
  # there is no bare-list clause here: measured, a `defp deps, do: [...]` body
  # arrives wrapped exactly as a `do` block's does.
  defp literal({:__block__, _meta, [list]} = node) when is_list(list),
    do: {:ok, list, Sourceror.get_range(node)}

  defp literal(_other), do: {:error, {:no_deps_list, :not_a_literal}}

  defp declared?(list, dep) do
    normalised = dep |> Code.string_to_quoted!() |> Macro.to_string()

    Enum.any?(list, &(Macro.to_string(&1) == normalised))
  end

  @doc """
  Appends `element` to the literal list at `list_range`, as source text.

  Shared with `Capstone.Source.ApplicationEx`, which appends a supervision child by
  exactly the same mechanics: patch at the LAST element's range so the author's
  formatting survives, or — for an empty list — at a zero-width point just
  inside the brackets, so that `mix new`'s commented-out examples are not
  deleted along with the list they sit in.

  `add_dep/2` does NOT use this: a dependency goes at the top of the list, a
  position `priv/meta/cache_component` records and the round trip compares.
  """
  @spec append_element(binary(), [Macro.t()], Sourceror.Range.t(), binary()) ::
          binary()
  def append_element(source, [], list_range, element),
    do: insert_into_empty(source, list_range, element)

  def append_element(source, list, list_range, element) do
    last = List.last(list)
    change = Macro.to_string(last) <> separator(list_range) <> element

    Sourceror.patch_string(source, [
      %Patch{range: Sourceror.get_range(last), change: change}
    ])
  end

  # `mix new` writes an EMPTY deps list holding two commented-out examples, so
  # there is no element to patch beside — and replacing the whole list would
  # delete those comments, which are the project's own content. Inserted
  # instead at a zero-width point just after the opening bracket.
  defp insert_into_empty(source, list_range, element) do
    column = list_range.start[:column]
    point = [line: list_range.start[:line], column: column + 1]

    Sourceror.patch_string(source, [
      %Patch{
        range: %Sourceror.Range{start: point, end: point},
        change: empty_change(list_range, element, column),
        preserve_indentation: false
      }
    ])
  end

  defp prepend(source, [], list_range, dep) do
    column = list_range.start[:column]
    point = [line: list_range.start[:line], column: column + 1]

    Sourceror.patch_string(source, [
      %Patch{
        range: %Sourceror.Range{start: point, end: point},
        change: empty_change(list_range, dep, column),
        preserve_indentation: false
      }
    ])
  end

  # Patched at the range of the FIRST ELEMENT rather than of the list itself:
  # replacing the whole list would reprint every element and lose the author's
  # formatting, which is the thing patch_string/2 is here to preserve.
  #
  # FIRST, not last, and this is a contract rather than a preference: a
  # plugin's dependency has always landed at the top of the list, and
  # priv/meta/cache_component records that — the round trip compares bytes.
  defp prepend(source, [first | _rest], list_range, dep) do
    change = dep <> separator(list_range) <> Macro.to_string(first)

    Sourceror.patch_string(source, [
      %Patch{range: Sourceror.get_range(first), change: change}
    ])
  end

  defp separator(%{start: [line: line, column: _], end: [line: line, column: _]}), do: ", "
  defp separator(_range), do: ",\n"

  # A one-line `[]` takes the element bare; a multi-line one takes it on its own
  # line, indented one past the opening bracket, with a trailing comma so that
  # `mix new`'s commented-out examples below it stay inside the list.
  defp empty_change(
         %{start: [line: line, column: _], end: [line: line, column: _]},
         dep,
         _column
       ),
       do: dep

  defp empty_change(_range, dep, column),
    do: "\n" <> String.duplicate(" ", column + 1) <> dep <> ","

  # `deps` is located by its own two-stage rule because a delegating project
  # names it twice. `project` and `aliases` are named once, so one walk to the
  # function is enough.
  defp keyword_list(quoted, name, absent) do
    case find(quoted, &function?(&1, name)) do
      nil -> {:error, absent}
      node -> literal_keyword(function_body(node), absent)
    end
  end

  defp function?({def_, _meta, [{name, _, _} | _rest]}, name) when def_ in [:def, :defp], do: true
  defp function?(_node, _name), do: false

  defp literal_keyword({:__block__, _meta, [list]} = node, _absent) when is_list(list),
    do: {:ok, list, Sourceror.get_range(node)}

  defp literal_keyword(_other, absent), do: {:error, absent}

  defp to_pairs(list) do
    for {{:__block__, _km, [key]}, value} <- list, do: {key, Macro.to_string(value)}
  end

  defp commands({:__block__, _meta, [list]}) when is_list(list),
    do: Enum.map(list, &Macro.to_string/1)

  defp commands(other), do: [Macro.to_string(other)]

  # Replace the VALUE's range when the key is present, append a pair when it is
  # not. Patching the value rather than the pair keeps the key's own spacing.
  defp put_pair(source, list, list_range, key, value) do
    case Enum.find(list, fn {{:__block__, _m, [k]}, _v} -> k == key end) do
      nil -> append_pair(source, list, list_range, key, value)
      {_key_node, current} -> replace_value(source, current, value)
    end
  end

  defp replace_value(source, current, value) do
    if Macro.to_string(current) == value do
      source
    else
      Sourceror.patch_string(source, [
        %Patch{range: Sourceror.get_range(current), change: value}
      ])
    end
  end

  defp append_pair(source, list, list_range, key, value) do
    last = List.last(list)
    change = pair_source(last) <> separator(list_range) <> "#{key_source(key)} #{value}"

    Sourceror.patch_string(source, [%Patch{range: pair_range(last), change: change}])
  end

  defp pair_source({{:__block__, _m, [key]}, value}),
    do: "#{key_source(key)} #{Macro.to_string(value)}"

  # `Macro.inspect_atom(:key, …)` and not "\#{key}:" — an alias like
  # :"assets.build" renders as `assets.build:` unquoted, which is a syntax
  # error, and every alias the Svelte layer adds is dotted.
  defp key_source(key), do: Macro.inspect_atom(:key, key)

  defp pair_range({{:__block__, _m, _k} = key_node, value}) do
    %{Sourceror.get_range(key_node) | end: Sourceror.get_range(value).end}
  end

  # Appended after the module body's LAST child, which is where a reader
  # expects a new private helper and where nothing else has to move.
  defp append_function(source, quoted, name, body) do
    last = quoted |> module_children() |> List.last()
    range = Sourceror.get_range(last)
    change = "\n\n  defp #{name} do\n    #{indent(body)}\n  end"

    Sourceror.patch_string(source, [
      %Patch{range: %{range | start: range.end}, change: change, preserve_indentation: false}
    ])
  end

  defp module_children({:defmodule, _meta, [_alias, [{{:__block__, _, [:do]}, body}]]}) do
    case body do
      {:__block__, _m, kids} -> kids
      only -> [only]
    end
  end

  defp indent(body), do: body |> String.split("\n") |> Enum.join("\n    ")
end

defmodule Capstone.Source.MixExs.Error do
  @moduledoc """
  Raised when a `mix.exs` construct a plugin must edit cannot be located.

  A plugin that cannot install its dependencies must fail at install time.
  Returning the source unchanged and reporting `:ok` is the defect this exists
  to make impossible.
  """
  defexception [:message]
end
