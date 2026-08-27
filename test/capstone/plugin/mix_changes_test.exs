defmodule Capstone.Plugin.MixChangesTest do
  use ExUnit.Case, async: true

  alias Capstone.Factory
  alias Capstone.Plugin.MixChanges
  alias Capstone.Source.MixExs

  @baseline """
  defmodule App.MixProject do
    use Mix.Project

    def project, do: [app: :app, deps: deps()]

    defp deps do
      [
        {:phoenix, "~> 1.8.9"},
        {:jason, "~> 1.4"}
      ]
    end
  end
  """

  test "reports dependencies the meta project added" do
    {:ok, meta} = MixExs.add_dep(@baseline, ~s|{:nebulex, "~> 2.6"}|)

    assert %{deps: [~s|{:nebulex, "~> 2.6"}|]} = MixChanges.added(@baseline, meta)
  end

  test "reports added dependencies from every shape mix accepts" do
    # Deps.declarations/1 matched two of these four and returned [] for the
    # rest, so a plugin captured from a `def deps do` project recorded no
    # dependencies at all and reported success.
    for shape <- [:defp_do, :def_do, :defp_keyword, :inline] do
      %{source: baseline} = Factory.build(:mix_exs_shape, shape: shape)
      {:ok, meta} = MixExs.add_dep(baseline, ~s|{:nebulex, "~> 2.6"}|)

      assert %{deps: [~s|{:nebulex, "~> 2.6"}|]} = MixChanges.added(baseline, meta),
             "shape #{shape}"
    end
  end

  test "an unchanged mix.exs changes nothing" do
    assert MixChanges.added(@baseline, @baseline) == %{deps: [], aliases: [], project: []}
  end

  test "reformatting is not an added dependency" do
    # The reason this reads the AST rather than the text: a textual diff would
    # report every reflowed line as a change.
    reflowed =
      String.replace(@baseline, ~s|{:phoenix, "~> 1.8.9"},\n      |, ~s|{:phoenix, "~> 1.8.9"}, |)

    assert %{deps: []} = MixChanges.added(@baseline, reflowed)
  end

  test "options on a dependency are preserved verbatim" do
    {:ok, meta} =
      MixExs.add_dep(@baseline, ~s|{:credo, "~> 1.7", only: [:dev, :test], runtime: false}|)

    assert %{deps: [~s|{:credo, "~> 1.7", only: [:dev, :test], runtime: false}|]} =
             MixChanges.added(@baseline, meta)
  end

  test "reports an added alias" do
    %{source: baseline} = Factory.build(:mix_exs_shape, shape: :with_aliases)
    {:ok, meta} = MixExs.put_alias(baseline, :"assets.build", [~s|"pnpm build"|])

    assert %{aliases: [{:"assets.build", [~s|"pnpm build"|]}]} =
             MixChanges.added(baseline, meta)
  end

  test "reports a REPLACED alias, not only a new one" do
    # A plugin that rewrites setup: is contributing that rewrite, and it has
    # no representation if only new keys count.
    %{source: baseline} = Factory.build(:mix_exs_shape, shape: :with_aliases)
    {:ok, meta} = MixExs.put_alias(baseline, :setup, [~s|"deps.get"|, ~s|"assets.setup"|])

    assert %{aliases: [{:setup, [~s|"deps.get"|, ~s|"assets.setup"|]}]} =
             MixChanges.added(baseline, meta)
  end

  test "reports an added project key" do
    %{source: baseline} = Factory.build(:mix_exs_shape)
    {:ok, meta} = MixExs.put_project_key(baseline, :listeners, "[Phoenix.CodeReloader]")

    assert %{project: [{:listeners, "[Phoenix.CodeReloader]"}]} =
             MixChanges.added(baseline, meta)
  end

  test "a mix.exs without any of the three constructs changes nothing" do
    # Absent is the ordinary case, not an error: a meta project with no
    # aliases/0 must not make derive fail.
    assert MixChanges.added("defmodule X do\nend\n", "defmodule X do\nend\n") ==
             %{deps: [], aliases: [], project: []}
  end
end
