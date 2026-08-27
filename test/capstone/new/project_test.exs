defmodule Capstone.New.ProjectTest do
  use ExUnit.Case, async: true

  alias Capstone.New.Factory
  alias Capstone.New.Project

  # No path reaching out of this project appears anywhere in this file. The
  # generator baselines belong to the other perimeter and do not exist here; the
  # "patches the real stock mix.exs" assertion lives in the root suite, which
  # owns those files.

  test "patch_mix_exs/2 inserts the dep first and the result still parses" do
    %{source: source} = Factory.build(:mix_exs_source, variety: :stock_otp)

    {:ok, patched} =
      Project.patch_mix_exs(source, ~s|{:capstone, path: "/r", only: [:dev], runtime: false}|)

    assert patched =~ ":capstone"
    assert Code.string_to_quoted!(patched, emit_warnings: false)
  end

  test "patch_mix_exs/2 leaves an existing dep intact and adds exactly one line" do
    %{source: source} = Factory.build(:mix_exs_source, variety: :stock_web)

    {:ok, patched} = Project.patch_mix_exs(source, ~s|{:capstone, "~> 0.1"}|)

    assert patched =~ "{:phoenix,"
    assert length(String.split(patched, "\n")) == length(String.split(source, "\n")) + 1
  end

  test "patch_mix_exs/2 puts the dep inside deps/0, not merely somewhere in the file" do
    # A patch that appended to the end of the file would satisfy `=~ ":capstone"`
    # and still parse, while producing a project that does not resolve the dep.
    %{source: source} = Factory.build(:mix_exs_source, variety: :stock_otp)

    {:ok, patched} = Project.patch_mix_exs(source, ~s|{:capstone, "~> 0.1"}|)

    assert [{:capstone, "~> 0.1"} | _rest] = deps_of(patched)
  end

  test "patch_mix_exs/2 reports a missing anchor rather than silently doing nothing" do
    %{source: source} = Factory.build(:mix_exs_source, variety: :no_deps_block)

    assert Project.patch_mix_exs(source, "x") == {:error, :deps_not_found}
  end

  test "patch_mix_exs/2 reports an already-patched project" do
    %{source: source} = Factory.build(:mix_exs_source, variety: :already_patched)

    assert Project.patch_mix_exs(source, "x") == {:error, :already_patched}
  end

  test "patch_mix_exs/2 is not idempotent-by-accident: patching twice is refused" do
    %{source: source} = Factory.build(:mix_exs_source, variety: :stock_otp)
    {:ok, once} = Project.patch_mix_exs(source, ~s|{:capstone, "~> 0.1"}|)

    assert Project.patch_mix_exs(once, ~s|{:capstone, "~> 0.1"}|) == {:error, :already_patched}
  end

  test "render_config/1 produces exactly the SDD 8.1 keys with plugins: []" do
    opts = Factory.build(:options, name: "my_app", app: :my_app, module: MyApp, base: :web)

    {:%{}, _meta, pairs} =
      opts |> Project.render_config() |> Code.string_to_quoted!(emit_warnings: false)

    # `plugins`, not `components`: the root package's config reader names it
    # that way in its top-level key list and rejects the file outright when it
    # is absent, so the key IS the contract. Named by description rather than by
    # module, because the perimeter check in quality_gate_test.exs scans prose
    # too and cannot tell a mention from a call.
    assert pairs |> Enum.map(&elem(&1, 0)) |> Enum.sort() ==
             [:base, :plugins, :project, :schema_version]

    assert {:plugins, []} in pairs
  end

  test "render_config/1 carries every project field through" do
    opts =
      Factory.build(:options,
        name: "my_app",
        app: :my_app,
        module: MyApp,
        base: :web,
        github_org: "acme"
      )

    rendered = Project.render_config(opts)

    assert rendered =~ ~s|name: "my_app"|
    assert rendered =~ "module: MyApp"
    assert rendered =~ "app: :my_app"
    assert rendered =~ ~s|github_org: "acme"|
    assert rendered =~ "base: :web"
  end

  test "render_config/1 is byte-identical across 50 calls and ends with one newline" do
    opts = Factory.build(:options)

    assert [rendered] = 1..50 |> Enum.map(fn _n -> Project.render_config(opts) end) |> Enum.uniq()
    assert String.ends_with?(rendered, "}\n")
    refute String.ends_with?(rendered, "\n\n")
  end

  test "render_config/1 renders the options' plugins list" do
    opts = Factory.build(:options, base: :web, plugins: [:cache, :openapi])
    rendered = Project.render_config(opts)

    assert {:ok, config} = Capstone.Config.read_string(rendered)
    assert config.plugins == [:cache, :openapi]
  end

  test "render_config/1 still renders an empty list when there are no plugins" do
    opts = Factory.build(:options, base: :web, plugins: [])

    assert {:ok, config} = Capstone.Config.read_string(Project.render_config(opts))
    assert config.plugins == []
  end

  defp deps_of(source) do
    {ast, _binding} =
      source
      |> Code.string_to_quoted!(emit_warnings: false)
      |> Macro.prewalk([], fn node, acc -> {node, acc} end)
      |> elem(0)
      |> then(&{&1, []})

    {:defmodule, _meta, [_alias, [do: body]]} = ast

    body
    |> block_exprs()
    |> Enum.find_value(&deps_literal/1)
  end

  defp block_exprs({:__block__, _meta, exprs}), do: exprs
  defp block_exprs(expr), do: [expr]

  defp deps_literal({:defp, _meta, [{:deps, _dm, _args}, [do: list]]}), do: eval_literal(list)
  defp deps_literal(_expr), do: nil

  defp eval_literal(ast) do
    {value, _binding} = Code.eval_quoted(ast)

    value
  end
end
