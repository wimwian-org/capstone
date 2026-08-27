defmodule Capstone.Plugin.DeriveTest do
  use ExUnit.Case, async: true

  alias Capstone.Factory
  alias Capstone.Plugin
  alias Capstone.Plugin.Derive

  setup do
    %{baseline: baseline, meta: meta} = Factory.build(:meta_pair)
    out = Path.join(System.tmp_dir!(), "plugin-out-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(out) end)

    opts = [
      name: :cache,
      baseline: baseline,
      meta: meta,
      names: %{module: "App", app: "app", name: "app"},
      out: out
    ]

    {:ok, opts: opts, out: out}
  end

  test "classifies every change into its bucket", %{opts: opts} do
    assert {:ok, plugin} = Derive.run(opts)

    assert plugin.name == :cache
    assert {"lib/APP/cache.ex", :sole_owner} in plugin.files
    assert {"config/config.exs", :contributes, [key: :cache_config]} in plugin.files

    # A supervision child is PLACED, not marked: adding a list element rewrites
    # the previous last entry to gain a comma, which read as a deletion and
    # produced a conflict region in every generated project.
    assert {"lib/APP/application.ex", :contributes,
            [key: :cache_application, child: "<%= @module %>.Cache"]} in plugin.files

    # mix.exs is extracted to deps: and never becomes a file entry.
    assert plugin.deps == [~s|{:nebulex, "~> 2.6"}|]
    refute Enum.any?(plugin.files, &(elem(&1, 0) == "mix.exs"))
  end

  test "writes a templated payload for every file entry", %{opts: opts, out: out} do
    assert {:ok, _component} = Derive.run(opts)

    sole_owner = File.read!(Path.join(out, "files/lib/APP/cache.ex.eex"))
    assert sole_owner == "defmodule <%= @module %>.Cache do\nend\n"

    # A :contributes entry ships the block alone, not the whole file.
    block = File.read!(Path.join(out, "files/config/config.exs.block.eex"))
    assert block =~ "config :<%= @app %>, <%= @module %>.Cache"
    refute block =~ "import Config"
  end

  test "refuses a deletion, naming the path", %{opts: opts} do
    File.rm!(Path.join(opts[:meta], "config/config.exs"))

    assert {:error, {:unrepresentable_deletions, ["config/config.exs"]}} = Derive.run(opts)
  end

  test "preserves author-owned fields across a re-derive", %{opts: opts, out: out} do
    assert {:ok, _first} = Derive.run(opts)

    manifest = Path.join(out, "manifest.exs")

    manifest
    |> Plugin.read!()
    |> Map.put(:version, "9.9.9")
    |> Map.put(:provides, [:cache_backend])
    |> then(&Plugin.write!(manifest, &1))

    assert {:ok, second} = Derive.run(opts)

    # Derive is a read-modify-write, not a regenerate. Without this 10.1's
    # author-confirmed annotations would be discarded on every run, and 10's
    # "CI can assert derive reproduces the plugin" could never hold.
    assert second.version == "9.9.9"
    assert second.provides == [:cache_backend]
  end

  test "is deterministic", %{opts: opts, out: out} do
    assert {:ok, _} = Derive.run(opts)
    first = File.read!(Path.join(out, "manifest.exs"))

    assert {:ok, _} = Derive.run(opts)
    assert File.read!(Path.join(out, "manifest.exs")) == first
  end

  test "records where a config contribution was observed, not where it is easiest" do
    # Observed, not guessed — the same rule the whole capture side runs on. The
    # meta project put its block ABOVE import_config, so the plugin must say
    # so, or apply appends it below and it silently outranks dev/test/prod.
    %{baseline: baseline, meta: meta} = Factory.build(:meta_pair, variety: :configuring)
    out = Path.join(System.tmp_dir!(), "derive-cfg-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(out) end)

    {:ok, plugin} =
      Derive.run(
        name: :svelte,
        baseline: baseline,
        meta: meta,
        names: %{app: "myapp", module: "Myapp", name: "myapp"},
        out: out
      )

    assert [{"config/config.exs", :contributes, opts}] = plugin.files
    assert Keyword.fetch!(opts, :at) == :before_import
  end

  test "omits at: entirely when the contribution simply appends" do
    # No plugin gains a key that says nothing, and priv/meta/meta_cache
    # must reproduce byte for byte.
    %{baseline: baseline, meta: meta} = Factory.build(:meta_pair)
    out = Path.join(System.tmp_dir!(), "derive-app-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(out) end)

    {:ok, plugin} =
      Derive.run(
        name: :cache,
        baseline: baseline,
        meta: meta,
        names: %{module: "App", app: "app", name: "app"},
        out: out
      )

    assert {"config/config.exs", :contributes, opts} =
             Enum.find(plugin.files, &(elem(&1, 0) == "config/config.exs"))

    refute Keyword.has_key?(opts, :at)
  end

  test "records a runtime.exs contribution as belonging inside its env guard" do
    %{baseline: baseline, meta: meta} = Factory.build(:meta_pair, variety: :configuring_runtime)
    out = Path.join(System.tmp_dir!(), "derive-rt-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(out) end)

    {:ok, plugin} =
      Derive.run(
        name: :svelte,
        baseline: baseline,
        meta: meta,
        names: %{app: "myapp", module: "Myapp", name: "myapp"},
        out: out
      )

    assert [{"config/runtime.exs", :contributes, opts}] = plugin.files
    assert Keyword.fetch!(opts, :at) == {:env, :prod}
  end

  test "falls through to :manual when no placement reproduces the observed file" do
    # Loud beats wrong: apply would otherwise append the block, and appending
    # is what puts a contribution below import_config where it silently
    # outranks the project's own dev.exs, test.exs and prod.exs.
    %{baseline: baseline, meta: meta} =
      Factory.build(:meta_pair, variety: :configuring_unplaceable)

    out = Path.join(System.tmp_dir!(), "derive-un-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(out) end)

    {:ok, plugin} =
      Derive.run(
        name: :svelte,
        baseline: baseline,
        meta: meta,
        names: %{app: "myapp", module: "Myapp", name: "myapp"},
        out: out
      )

    assert [{"config/config.exs", :manual, _opts}] = plugin.files
  end

  describe "a plugin that adds a supervision child" do
    @names %{app: "myapp", module: "Myapp", name: "myapp"}

    defp derive_variety(variety, name) do
      %{baseline: baseline, meta: meta} = Factory.build(:meta_pair, variety: variety)
      out = Path.join(System.tmp_dir!(), "derive-sup-#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(out) end)

      {:ok, plugin} =
        Derive.run(name: name, baseline: baseline, meta: meta, names: @names, out: out)

      {plugin, out}
    end

    test "emits a child: entry and records no removal" do
      # The measured defect: adding a list element rewrites the previous last
      # entry to gain a comma, so Diff reports a removal, file_mode forces
      # :manual, and mark_removal writes a conflict region on every install.
      {plugin, out} = derive_variety(:supervised, :cache)

      assert [{"lib/APP/application.ex", :contributes, opts}] = plugin.files
      assert Keyword.fetch!(opts, :child) == "<%= @module %>.Cache"
      assert Path.wildcard(Path.join(out, "files/**/application.ex.removed.eex")) == []
    end

    test "ships no block payload for a child: entry" do
      {_component, out} = derive_variety(:supervised, :cache)

      assert Path.wildcard(Path.join(out, "files/**/application.ex.block.eex")) == []
    end

    test "a change beyond the children list still falls through to :manual" do
      # The guard is not weakened; it stops firing on the one shape that has a
      # deterministic answer.
      {plugin, _out} = derive_variety(:supervised_and_strategy, :cache)

      assert [{"lib/APP/application.ex", :manual, _opts}] = plugin.files
    end
  end

  test "records an alias the meta project added" do
    # Nothing captured this before MixChanges widened: derive.ex extracted only
    # the deps list, so aliases/0 and project/0 keys had no representation at
    # all — not a placement bug, a missing capability the Svelte layer needs.
    %{baseline: baseline, meta: meta} = Factory.build(:meta_pair, variety: :aliasing)
    out = Path.join(System.tmp_dir!(), "derive-alias-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(out) end)

    {:ok, plugin} =
      Derive.run(
        name: :svelte,
        baseline: baseline,
        meta: meta,
        names: %{app: "myapp", module: "Myapp", name: "myapp"},
        out: out
      )

    assert plugin.aliases == [{:"assets.build", [~s|"cmd --cd assets pnpm build"|]}]
    assert plugin.deps == []

    # The wiring is captured too, and that is right rather than redundant: the
    # meta project's project/0 really does gain `aliases: aliases()`, and
    # capture reports what changed. Apply doing it twice is harmless because
    # put_project_key/3 is idempotent.
    assert plugin.project == [{:aliases, "aliases()"}]
  end

  test "drops an empty aliases: and project: rather than writing them" do
    # No plugin gains a key that says nothing, which is also what keeps
    # priv/meta/meta_cache reproducing byte for byte.
    %{baseline: baseline, meta: meta} = Factory.build(:meta_pair)
    out = Path.join(System.tmp_dir!(), "derive-empty-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(out) end)

    {:ok, plugin} =
      Derive.run(
        name: :cache,
        baseline: baseline,
        meta: meta,
        names: %{module: "App", app: "app", name: "app"},
        out: out
      )

    refute Map.has_key?(plugin, :aliases)
    refute Map.has_key?(plugin, :project)
  end

  describe "a file that removes lines" do
    setup do
      %{baseline: baseline, meta: meta} = Factory.build(:meta_pair, variety: :rewrite)
      out = Path.join(System.tmp_dir!(), "derive-del-#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(out) end)

      opts = [
        name: :svelte,
        baseline: baseline,
        meta: meta,
        names: %{app: "myapp", module: "Myapp", name: "myapp"},
        out: out
      ]

      {:ok, opts: opts, out: out}
    end

    test "is :manual even though its extension would classify as :contributes", %{opts: opts} do
      {:ok, plugin} = Derive.run(opts)

      # The reproduced defect. .css is not Elixir, so Classify.bucket/2 sends
      # every hunk in it to :contributes, and apply APPENDED the replacement
      # beside the content it was meant to replace.
      [{path, mode, entry_opts}] = plugin.files

      assert path == "assets/css/app.css"
      assert mode == :manual
      assert Keyword.fetch!(entry_opts, :key) == :svelte_app
    end

    test "ships the removed lines as a second payload", %{opts: opts, out: out} do
      {:ok, _component} = Derive.run(opts)

      assert File.read!(Path.join(out, "files/assets/css/app.css.removed.eex")) ==
               "@plugin \"daisyui\";"

      assert File.exists?(Path.join(out, "files/assets/css/app.css.block.eex"))
    end

    test "templates the removed lines, which come from the baseline" do
      # The removed line carries the meta project's own name. Shipped raw it
      # would never match a target called anything else, and the deletion would
      # read as already-done.
      %{baseline: baseline, meta: meta} = Factory.build(:meta_pair, variety: :deleting)
      out = Path.join(System.tmp_dir!(), "derive-del-#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(out) end)

      {:ok, _component} =
        Derive.run(
          name: :trim,
          baseline: baseline,
          meta: meta,
          names: %{app: "myapp", module: "Myapp", name: "myapp"},
          out: out
        )

      assert File.read!(Path.join(out, "files/config/config.exs.removed.eex")) ==
               "config :<%= @app %>, legacy: true"
    end

    test "a file with no deletions ships no removed payload", %{out: out} do
      %{baseline: baseline, meta: meta} = Factory.build(:meta_pair)

      {:ok, _component} =
        Derive.run(
          name: :cache,
          baseline: baseline,
          meta: meta,
          names: %{module: "App", app: "app", name: "app"},
          out: out
        )

      # Neither ships one. config.exs appends and removes nothing; and
      # application.ex, which inserts into a list literal and so DID record the
      # deleted line that gains the comma, is now recognised as a supervision
      # child instead — removing the cause rather than the guard. The positive
      # control for a recorded deletion is the :rewrite variety above.
      refute File.exists?(Path.join(out, "files/config/config.exs.removed.eex"))
      refute File.exists?(Path.join(out, "files/lib/APP/application.ex.removed.eex"))
    end

    test "a whole-file deletion is still refused" do
      %{baseline: baseline, meta: meta} = Factory.build(:meta_pair, variety: :whole_file)
      out = Path.join(System.tmp_dir!(), "derive-del-#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(out) end)

      # Unchanged: there is no hunk to mark up when the file itself is gone.
      assert Derive.run(
               name: :svelte,
               baseline: baseline,
               meta: meta,
               names: %{app: "myapp", module: "Myapp", name: "myapp"},
               out: out
             ) == {:error, {:unrepresentable_deletions, ["assets/css/app.css"]}}
    end
  end
end
