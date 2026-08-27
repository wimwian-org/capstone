defmodule Capstone.Source.ApplicationEx do
  @moduledoc """
  Adds a child to a project's supervision tree, structurally.

  The most common structural edit a plugin makes — a cache, a job queue, a
  connection pool, a watcher — and the one that adding a list element makes
  look like a deletion: the previous last entry is rewritten to gain a comma,
  so `Capstone.Plugin.Diff` reports a removal and
  `2026-08-14-deletion-representation-design.md` §1 forces the whole file to
  `:manual`. That is correct and loud, and it made every such plugin
  require a hand edit in every generated project. This module removes the
  cause rather than relaxing the guard.

  Scoped to the `children` binding inside `start/2`, deliberately. A general
  list editor addressed by AST path has no second caller, and every extra shape
  it accepts is one nobody has verified.

  Source text in, source text out, no filesystem — the shape
  `Capstone.Source.MixExs` established, over the same `Capstone.Vendor.Sourceror` engine.
  """

  alias Capstone.Vendor.Sourceror

  alias Capstone.Source.MixExs
  alias Capstone.Vendor.Sourceror.Zipper

  @typedoc "Every reason adding a child to `start/2`'s supervision list can fail."
  @type error ::
          {:no_start_function, :not_found}
          | {:children_not_a_literal, :start}
          | {:unparseable, term()}

  @doc """
  The supervision children declared in `start/2`, as the strings the author
  wrote.

  Commented-out examples are comments, not children: `mix new --sup` and
  `phx.new` both ship one, and a textual reader would count them.
  """
  @spec children(binary()) :: {:ok, [binary()]} | {:error, error()}
  def children(source) do
    with {:ok, quoted} <- parse(source),
         {:ok, list, _range} <- children_list(quoted) do
      {:ok, Enum.map(list, &Macro.to_string/1)}
    end
  end

  @doc """
  Appends `child` to the supervision tree.

  LAST, always. Supervision order is a semantic the plugin cannot reason
  about: it knows its own process needs the repo started first, but not whether
  it should precede another plugin's. After everything the project already
  had is the only position that is both deterministic and defensible, and
  prepending would let a plugin's process start before the project's own.

  Idempotent by parsed comparison, not by substring: two identical children are
  a name clash at boot.

  A `children` built by a function call, a comprehension or `++` returns
  `{:error, {:children_not_a_literal, :start}}` and the caller falls back to
  the `:manual` path it used before this module existed. Failing into the
  existing loud behaviour is the correct degradation.
  """
  @spec add_child(binary(), binary()) :: {:ok, binary()} | {:error, error()}
  def add_child(source, child) do
    with {:ok, quoted} <- parse(source),
         {:ok, list, range} <- children_list(quoted) do
      if declared?(list, child),
        do: {:ok, source},
        else: {:ok, MixExs.append_element(source, list, range, child)}
    end
  end

  defp parse(source) do
    {:ok, Sourceror.parse_string!(source)}
  rescue
    error -> {:error, {:unparseable, error}}
  end

  defp children_list(quoted) do
    with {:ok, body} <- start_body(quoted),
         {:ok, assignment} <- children_assignment(body) do
      literal(assignment)
    end
  end

  defp start_body(quoted) do
    quoted
    |> Zipper.zip()
    |> Zipper.find(&start_function?/1)
    |> case do
      nil -> {:error, {:no_start_function, :not_found}}
      zipper -> {:ok, Zipper.node(zipper)}
    end
  end

  defp start_function?({:def, _meta, [{:start, _, _} | _rest]}), do: true
  defp start_function?(_node), do: false

  # Located by the BINDING's name inside start/2, not by "the first list in the
  # function": a project that calls its list something else gets a named error
  # and a conflict region, where matching any list would place a child into
  # whichever literal came first.
  defp children_assignment(node) do
    node
    |> Zipper.zip()
    |> Zipper.find(&children_binding?/1)
    |> case do
      nil -> {:error, {:children_not_a_literal, :start}}
      zipper -> {:ok, zipper |> Zipper.node() |> elem(2) |> List.last()}
    end
  end

  defp children_binding?({:=, _meta, [{:children, _, nil}, _value]}), do: true
  defp children_binding?(_node), do: false

  defp literal({:__block__, _meta, [list]} = node) when is_list(list),
    do: {:ok, list, Sourceror.get_range(node)}

  defp literal(_other), do: {:error, {:children_not_a_literal, :start}}

  defp declared?(list, child) do
    normalised = child |> Code.string_to_quoted!() |> Macro.to_string()

    Enum.any?(list, &(Macro.to_string(&1) == normalised))
  end
end

defmodule Capstone.Source.ApplicationEx.Error do
  @moduledoc """
  Raised when a supervision tree a plugin must extend cannot be located.

  A plugin whose process is never started is a plugin that did nothing,
  and reporting `:ok` for it is the silent-success shape this whole subsystem
  exists to remove.
  """
  defexception [:message]
end
