defmodule Capstone.Credo.Check.Design.NoRuntimeDeps do
  @moduledoc """
  Flags a dependency in `mix.exs` that is not excluded from `:prod`.

  Capstone is installed as a dev dependency **inside someone else's project**, so
  every requirement it declares becomes a constraint on that project's
  resolution. A project already using Igniter or Ash carries its own Sourceror
  pin; if Capstone declared a conflicting one, hex would refuse to resolve and the
  scaffolder would be locked out of the very project it needs to update six
  months later. That is why `vendor/` exists.

  The rule is `only:` excluding `:prod` — **not** `runtime: false`. A
  `runtime: false` dependency is still resolved by hex and still propagates to
  dependents; it merely is not started. `runtime: false` is about the
  application boot sequence, `only:` is about the dependency graph, and only the
  second one is what this check is protecting.

      # flagged -- reaches the target's graph
      {:sourceror, "~> 1.12"}
      {:sourceror, "~> 1.12", runtime: false}

      # fine -- Capstone's own toolchain, invisible to the target
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}

  An `only:` this check cannot read as a literal is treated as reaching `:prod`.
  A dependency whose scope cannot be proven is exactly the one worth looking at.

  This check is specific to Capstone and is deliberately **not** part of the
  boilerplate shipped to generated projects: a generated application is supposed
  to have runtime dependencies.
  """

  use Credo.Check,
    base_priority: :high,
    category: :design,
    exit_status: 2,
    explanations: [check: @moduledoc]

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    if mix_exs?(source_file) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse/2)
      |> Enum.map(&issue_for(issue_meta, &1))
    else
      []
    end
  end

  defp mix_exs?(source_file), do: Path.basename(source_file.filename) == "mix.exs"

  defp traverse({kind, meta, [{:deps, _, _}, [do: deps]]} = ast, acc)
       when kind in [:def, :defp] do
    {ast, acc ++ Enum.map(offenders(deps), &{meta[:line], &1})}
  end

  defp traverse(ast, acc), do: {ast, acc}

  defp offenders(deps) when is_list(deps) do
    deps
    |> Enum.map(&dep_scope/1)
    |> Enum.reject(fn {_name, opts} -> excluded_from_prod?(opts) end)
    |> Enum.map(fn {name, _opts} -> name end)
  end

  defp offenders(_not_a_literal_list), do: []

  # `{:credo, "~> 1.7"}` and `{:capstone, path: "../capstone"}` -- a two-element tuple
  # is its own AST literal and carries no metadata, which is why issues are
  # reported against the `deps/0` line rather than the entry's own.
  defp dep_scope({name, second}) when is_atom(name) do
    if Keyword.keyword?(second), do: {name, second}, else: {name, []}
  end

  # Three-element tuples are wrapped: `{:{}, meta, [name, requirement, opts]}`.
  defp dep_scope({:{}, _meta, [name, _requirement, opts]}) when is_atom(name) do
    if Keyword.keyword?(opts), do: {name, opts}, else: {name, []}
  end

  defp dep_scope(other), do: {other, []}

  defp excluded_from_prod?(opts) do
    case Keyword.fetch(opts, :only) do
      {:ok, envs} -> prod_free?(envs)
      :error -> false
    end
  end

  defp prod_free?(env) when is_atom(env), do: env != :prod

  defp prod_free?(envs) when is_list(envs) do
    Enum.all?(envs, &is_atom/1) and :prod not in envs
  end

  defp prod_free?(_unreadable), do: false

  defp issue_for(issue_meta, {line_no, name}) do
    format_issue(issue_meta,
      message:
        "Dependency #{inspect(name)} is not excluded from :prod, so it would constrain " <>
          "the resolution of every project Capstone is installed into. Add `only:` " <>
          "(runtime: false is not enough), or vendor it.",
      trigger: to_string(name),
      line_no: line_no
    )
  end
end
