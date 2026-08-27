defmodule Capstone.Plugin.ApplyTest do
  use ExUnit.Case, async: true

  alias Capstone.Factory
  alias Capstone.Plugin.Apply
  alias Capstone.Source.MixExs

  describe "names/1" do
    test "reads the triple from the target's own mix.exs" do
      assert Apply.names("priv/meta/baseline_otp") == %{
               module: "NewOtpApp",
               app: "new_otp_app",
               name: "new_otp_app"
             }
    end

    test "a mix.exs with no app: is refused" do
      dir = Path.join(System.tmp_dir!(), "noapp-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "mix.exs"), "defmodule X do\nend\n")
      on_exit(fn -> File.rm_rf!(dir) end)

      assert_raise ArgumentError, ~r/no app: in/, fn -> Apply.names(dir) end
    end
  end

  describe "write_owned/4" do
    setup :target

    test "renders into the resolved path", %{target: target, names: names} do
      Apply.write_owned(
        target,
        "lib/APP/cache.ex",
        "defmodule <%= @module %>.Cache do\nend\n",
        names
      )

      assert File.read!(Path.join(target, "lib/tgt_app/cache.ex")) ==
               "defmodule TgtApp.Cache do\nend\n"
    end

    test "creates intermediate directories", %{target: target, names: names} do
      Apply.write_owned(target, "lib/APP/deep/nested.ex", "x\n", names)

      assert File.exists?(Path.join(target, "lib/tgt_app/deep/nested.ex"))
    end
  end

  describe "place/6" do
    setup :target

    @module_line "defmodule TgtApp do"
    @alias_template "  alias <%= @module %>.Cache\n"

    test "inserts after a unique anchor", %{target: t, names: names} do
      file = seed(t, "lib/tgt_app.ex", "#{@module_line}\n  def hello, do: :ok\nend\n")

      Apply.place(t, "lib/APP.ex", @alias_template, :cache_app, [@module_line], names)

      assert File.read!(file) == """
             defmodule TgtApp do
               alias TgtApp.Cache
               def hello, do: :ok
             end
             """
    end

    test "falls back to a keyed marker when the anchor is ambiguous", %{target: t, names: names} do
      # Two identical anchor lines: placing against either would be a guess, and
      # a wrong guess is silent. This is the case that forced a 3-line anchor.
      file = seed(t, "lib/tgt_app.ex", "  end\n  x\n  end\n")

      Apply.place(t, "lib/APP.ex", @alias_template, :cache_app, ["  end"], names)

      contents = File.read!(file)
      assert contents =~ Apply.marker_prefix(:cache_app)
      assert contents =~ ">" <> String.duplicate(">", 6) <> " capstone: cache_app"
    end

    test "falls back to a marker when the anchor is absent", %{target: t, names: names} do
      file = seed(t, "lib/tgt_app.ex", "defmodule TgtApp do\nend\n")

      Apply.place(t, "lib/APP.ex", "  x\n", :cache_app, ["nowhere to be found"], names)

      assert File.read!(file) =~ Apply.marker_prefix(:cache_app)
    end

    test "an empty anchor marks rather than guessing", %{target: t, names: names} do
      file = seed(t, "lib/tgt_app.ex", "defmodule TgtApp do\nend\n")

      Apply.place(t, "lib/APP.ex", "  x\n", :cache_app, [], names)

      assert File.read!(file) =~ Apply.marker_prefix(:cache_app)
    end

    test "is a no-op on a second application", %{target: t, names: names} do
      file = seed(t, "lib/tgt_app.ex", "#{@module_line}\nend\n")

      Apply.place(t, "lib/APP.ex", @alias_template, :cache_app, [@module_line], names)
      once = File.read!(file)
      Apply.place(t, "lib/APP.ex", @alias_template, :cache_app, [@module_line], names)

      assert File.read!(file) == once
    end

    test "a marked region is not re-marked", %{target: t, names: names} do
      file = seed(t, "lib/tgt_app.ex", "defmodule TgtApp do\nend\n")

      Apply.place(t, "lib/APP.ex", "  x\n", :cache_app, [], names)
      once = File.read!(file)
      Apply.place(t, "lib/APP.ex", "  x\n", :cache_app, [], names)

      assert File.read!(file) == once
    end
  end

  describe "mark_removal/6" do
    setup :target

    @css ~s|@import "tailwindcss" source(none);\n@plugin "daisyui";\n|
    @added ~s|@source "../svelte";\n|
    @removed ~s|@plugin "daisyui";|

    test "writes both halves into one keyed region", %{target: t, names: names} do
      file = seed(t, "assets/css/app.css", @css)

      Apply.mark_removal(t, "assets/css/app.css", @added, :svelte_app, names, @removed)

      contents = File.read!(file)

      assert contents =~ Apply.marker_prefix(:svelte_app)
      # BOTH halves, in one place: a human cannot resolve a removal they cannot
      # see, and D12 forbids asking them.
      assert contents =~ ~s|@plugin "daisyui";|
      assert contents =~ ~s|@source "../svelte";|
    end

    test "never anchors, even when the removed text is unique", %{target: t, names: names} do
      file = seed(t, "assets/css/app.css", @css)

      # place/6 would have inserted the added lines after their anchor and left
      # the removed ones behind — the silent success this closes.
      Apply.mark_removal(t, "assets/css/app.css", @added, :svelte_app, names, @removed)

      assert File.read!(file) =~ Apply.marker_prefix(:svelte_app)
    end

    test "renders the removed template against the target's own name", %{
      target: t,
      names: names
    } do
      file = seed(t, "config/config.exs", "config :tgt_app, legacy: true\n")

      Apply.mark_removal(
        t,
        "config/config.exs",
        "",
        :trim_config,
        names,
        "config :<%= @app %>, legacy: true"
      )

      # Shipped raw, the removed line would carry the META project's name, never
      # match this target, and the removal would read as already done.
      assert File.read!(file) =~ Apply.marker_prefix(:trim_config)
    end

    test "an unresolved region is not marked twice", %{target: t, names: names} do
      file = seed(t, "assets/css/app.css", @css)

      Apply.mark_removal(t, "assets/css/app.css", @added, :svelte_app, names, @removed)
      once = File.read!(file)
      Apply.mark_removal(t, "assets/css/app.css", @added, :svelte_app, names, @removed)

      assert File.read!(file) == once
    end

    test "a resolved region is not re-marked", %{target: t, names: names} do
      # What a human leaves behind: the removed line gone, the added one kept,
      # markers deleted. The added half cannot be the probe — resolving a
      # removal means deleting text, so it is the REMOVED half that reports
      # whether the edit has been made.
      resolved = ~s|@import "tailwindcss" source(none);\n@source "../svelte";\n|
      file = seed(t, "assets/css/app.css", resolved)

      Apply.mark_removal(t, "assets/css/app.css", @added, :svelte_app, names, @removed)

      assert File.read!(file) == resolved
    end

    test "a hunk that only deletes still marks, though its block is empty", %{
      target: t,
      names: names
    } do
      # String.contains?(anything, "") is true, so probing the ADDED half here
      # would return :ok on the first apply and write nothing at all.
      file = seed(t, "assets/css/app.css", @css)

      Apply.mark_removal(t, "assets/css/app.css", "", :svelte_app, names, @removed)

      assert File.read!(file) =~ Apply.marker_prefix(:svelte_app)
    end
  end

  describe "add_deps/2" do
    setup :target

    @mix_exs """
    defmodule TgtApp.MixProject do
      use Mix.Project

      defp deps do
        [
          {:jason, "~> 1.4"}
        ]
      end
    end
    """

    test "inserts each dependency into deps/0", %{target: t} do
      File.write!(Path.join(t, "mix.exs"), @mix_exs)

      Apply.add_deps(t, [~s|{:nebulex, "~> 2.6"}|])

      assert File.read!(Path.join(t, "mix.exs")) =~ ~s|      {:nebulex, "~> 2.6"},\n      {:jason|
    end

    test "is a no-op when the dependency is already declared", %{target: t} do
      File.write!(Path.join(t, "mix.exs"), @mix_exs)

      Apply.add_deps(t, [~s|{:jason, "~> 1.4"}|])

      assert File.read!(Path.join(t, "mix.exs")) == @mix_exs
    end

    test "an empty list leaves mix.exs untouched", %{target: t} do
      File.write!(Path.join(t, "mix.exs"), @mix_exs)

      Apply.add_deps(t, [])

      assert File.read!(Path.join(t, "mix.exs")) == @mix_exs
    end

    test "a reflowed declaration is still recognised as present", %{target: t} do
      # Read structurally: a textual check would treat this as absent and add a
      # duplicate, which mix rejects at compile time.
      reflowed = String.replace(@mix_exs, "[\n      {:jason", "[{:jason")
      File.write!(Path.join(t, "mix.exs"), reflowed)

      Apply.add_deps(t, [~s|{:jason, "~> 1.4"}|])

      assert File.read!(Path.join(t, "mix.exs")) == reflowed
    end

    test "writes the dependency into every shape mix accepts", %{target: t} do
      # Measured before the fix: three of these four wrote nothing and returned
      # :ok, so the plugin reported success and the target did not compile.
      for shape <- [:defp_do, :def_do, :defp_keyword, :inline] do
        %{source: source} = Factory.build(:mix_exs_shape, shape: shape)
        File.write!(Path.join(t, "mix.exs"), source)

        Apply.add_deps(t, [~s|{:live_svelte, "~> 0.18"}|])

        assert File.read!(Path.join(t, "mix.exs")) =~ "live_svelte", "shape #{shape}"
      end
    end

    test "raises rather than silently skipping an unlocatable list", %{target: t} do
      %{source: source} = Factory.build(:mix_exs_shape, shape: :computed)
      File.write!(Path.join(t, "mix.exs"), source)

      assert_raise MixExs.Error, ~r/no_deps_list/, fn ->
        Apply.add_deps(t, [~s|{:live_svelte, "~> 0.18"}|])
      end
    end
  end

  describe "put_aliases/2 and put_project_keys/2" do
    setup :target

    test "creates aliases/0 on a project that has none", %{target: t} do
      %{source: source} = Factory.build(:mix_exs_shape, shape: :without_aliases)
      File.write!(Path.join(t, "mix.exs"), source)

      Apply.put_aliases(t, [{:"assets.build", [~s|"cmd --cd assets pnpm build"|]}])

      assert {:ok, aliases} = MixExs.aliases(File.read!(Path.join(t, "mix.exs")))
      assert aliases[:"assets.build"] == [~s|"cmd --cd assets pnpm build"|]
    end

    test "an empty list leaves mix.exs untouched", %{target: t} do
      %{source: source} = Factory.build(:mix_exs_shape)
      File.write!(Path.join(t, "mix.exs"), source)

      Apply.put_aliases(t, [])
      Apply.put_project_keys(t, [])

      assert File.read!(Path.join(t, "mix.exs")) == source
    end

    test "sets a project key", %{target: t} do
      %{source: source} = Factory.build(:mix_exs_shape)
      File.write!(Path.join(t, "mix.exs"), source)

      Apply.put_project_keys(t, [{:listeners, "[Phoenix.CodeReloader]"}])

      assert {:ok, keys} = MixExs.project_keys(File.read!(Path.join(t, "mix.exs")))
      assert keys[:listeners] == "[Phoenix.CodeReloader]"
    end

    test "raises when project/0 cannot be located", %{target: t} do
      %{source: source} = Factory.build(:mix_exs_shape, shape: :computed_project)
      File.write!(Path.join(t, "mix.exs"), source)

      assert_raise MixExs.Error, fn ->
        Apply.put_project_keys(t, [{:listeners, "[]"}])
      end
    end
  end

  describe "a config contribution" do
    setup :target

    @block "config :<%= @app %>, added: true\n"

    test "lands above import_config when at: :before_import", %{target: t, names: names} do
      file = seed(t, "config/config.exs", Factory.build(:config_shape).source)

      Apply.contribute(t, "config/config.exs", @block, names, at: :before_import)

      lines = t |> Path.join("config/config.exs") |> File.read!() |> String.split("\n")

      assert Enum.find_index(lines, &(&1 =~ "added: true")) <
               Enum.find_index(lines, &String.starts_with?(&1, "import_config"))

      assert File.read!(file) =~ "config :tgt_app, added: true"
    end

    test "appends when at: is absent, exactly as before", %{target: t, names: names} do
      # Every plugin written before this plan carries no at:, and must keep
      # behaving identically.
      file = seed(t, "config/config.exs", "import Config\n")

      Apply.contribute(t, "config/config.exs", @block, names, [])

      assert File.read!(file) == "import Config\nconfig :tgt_app, added: true\n"
    end

    test "appending twice adds the block once", %{target: t, names: names} do
      file = seed(t, "config/config.exs", "import Config\n")

      Apply.contribute(t, "config/config.exs", @block, names, [])
      once = File.read!(file)
      Apply.contribute(t, "config/config.exs", @block, names, [])

      assert File.read!(file) == once
    end

    test "lands inside the guard when at: {:env, :prod}", %{target: t, names: names} do
      source = Factory.build(:config_shape, shape: :with_env_guard).source
      file = seed(t, "config/runtime.exs", source)

      Apply.contribute(t, "config/runtime.exs", @block, names, at: {:env, :prod})

      contents = File.read!(file)
      [_before, inside] = String.split(contents, "if config_env() == :prod do", parts: 2)
      [guarded, _after] = String.split(inside, "\nend", parts: 2)
      assert guarded =~ "added: true"
    end

    test "raises when the named guard is absent", %{target: t, names: names} do
      # Appending instead is how a production-only secret becomes a test
      # default, so this must fail at install rather than fall back.
      seed(t, "config/runtime.exs", "import Config\n")

      assert_raise Capstone.Source.ConfigExs.Error, ~r/no_env_guard/, fn ->
        Apply.contribute(t, "config/runtime.exs", @block, names, at: {:env, :prod})
      end
    end

    test "is a no-op on a second application", %{target: t, names: names} do
      file = seed(t, "config/config.exs", Factory.build(:config_shape).source)

      Apply.contribute(t, "config/config.exs", @block, names, at: :before_import)
      once = File.read!(file)
      Apply.contribute(t, "config/config.exs", @block, names, at: :before_import)

      assert File.read!(file) == once
    end
  end

  describe "a child: contribution" do
    setup :target

    test "appends the child and writes no marker", %{target: t, names: names} do
      file = seed(t, "lib/tgt_app/application.ex", Factory.build(:application_shape).source)

      Apply.add_supervision_child(t, "lib/APP/application.ex", "<%= @module %>.Cache", names)

      contents = File.read!(file)
      assert contents =~ "TgtApp.Cache"
      refute contents =~ Apply.marker_prefix("")
      assert {:ok, _ast} = Code.string_to_quoted(contents)
    end

    test "raises when the list cannot be located", %{target: t, names: names} do
      seed(
        t,
        "lib/tgt_app/application.ex",
        Factory.build(:application_shape, shape: :computed).source
      )

      assert_raise Capstone.Source.ApplicationEx.Error, ~r/children_not_a_literal/, fn ->
        Apply.add_supervision_child(t, "lib/APP/application.ex", "<%= @module %>.Cache", names)
      end
    end

    test "applying twice adds the child once", %{target: t, names: names} do
      file = seed(t, "lib/tgt_app/application.ex", Factory.build(:application_shape).source)

      Apply.add_supervision_child(t, "lib/APP/application.ex", "<%= @module %>.Cache", names)
      once = File.read!(file)
      Apply.add_supervision_child(t, "lib/APP/application.ex", "<%= @module %>.Cache", names)

      assert File.read!(file) == once
    end

    test "is dispatched from a plugin's :contributes entry", %{target: t} do
      plugin = Path.join(System.tmp_dir!(), "child-comp-#{System.unique_integer([:positive])}")
      File.mkdir_p!(plugin)
      on_exit(fn -> File.rm_rf!(plugin) end)

      Capstone.Plugin.write!(Path.join(plugin, "manifest.exs"), %{
        name: :cache,
        version: "0.1.0",
        deps: [],
        files: [
          {"lib/APP/application.ex", :contributes,
           [key: :cache_child, child: "<%= @module %>.Cache"]}
        ]
      })

      File.write!(
        Path.join(t, "mix.exs"),
        "defmodule T.MixProject do\n  def project, do: [app: :tgt_app]\nend\n"
      )

      file = seed(t, "lib/tgt_app/application.ex", Factory.build(:application_shape).source)

      {:ok, _applied} = Apply.run(plugin, t)

      # A child: entry ships NO .block.eex — the child is one expression that
      # Template.render/2 resolves like any other payload.
      contents = File.read!(file)
      assert contents =~ "TgtApp.Cache"
      refute contents =~ Apply.marker_prefix("")
    end
  end

  describe "a put: entry" do
    setup :target

    test "replaces the key and writes no marker", %{target: t, names: names} do
      file = seed(t, "config/dev.exs", Factory.build(:config_shape, shape: :with_repo).source)

      Apply.put_config_key(t, "config/dev.exs", ~s|"dba4PG"|, names,
        put: {[:t, T.Repo], :password}
      )

      contents = File.read!(file)
      assert contents =~ ~s|password: "dba4PG"|
      refute contents =~ Apply.marker_prefix("")
    end

    test "is dispatched from a plugin's :manual entry", %{target: t} do
      # The whole path, through Apply.run/2: a put: entry overrides a key that
      # already exists and never reaches the marker branch, so the target is
      # left compiling rather than conflict-marked.
      plugin = Path.join(System.tmp_dir!(), "put-comp-#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(plugin, "files/config"))
      on_exit(fn -> File.rm_rf!(plugin) end)

      File.write!(Path.join(plugin, "files/config/dev.exs.block.eex"), ~s|"dba4PG"\n|)

      Capstone.Plugin.write!(Path.join(plugin, "manifest.exs"), %{
        name: :docker,
        version: "0.1.0",
        deps: [],
        files: [
          {"config/dev.exs", :manual, [key: :docker_password, put: {[:t, T.Repo], :password}]}
        ]
      })

      File.write!(
        Path.join(t, "mix.exs"),
        "defmodule T.MixProject do\n  def project, do: [app: :tgt_app]\nend\n"
      )

      file = seed(t, "config/dev.exs", Factory.build(:config_shape, shape: :with_repo).source)

      {:ok, _applied} = Apply.run(plugin, t)

      contents = File.read!(file)
      assert contents =~ ~s|password: "dba4PG"|
      refute contents =~ Apply.marker_prefix("")
    end

    test "raises when the statement is absent", %{target: t, names: names} do
      seed(t, "config/dev.exs", "import Config\n")

      assert_raise Capstone.Source.ConfigExs.Error, fn ->
        Apply.put_config_key(t, "config/dev.exs", ~s|"x"|, names, put: {[:t, T.Repo], :password})
      end
    end
  end

  defp target(_context) do
    target = Path.join(System.tmp_dir!(), "apply-target-#{System.unique_integer([:positive])}")
    File.mkdir_p!(target)
    on_exit(fn -> File.rm_rf!(target) end)

    {:ok, target: target, names: %{module: "TgtApp", app: "tgt_app", name: "tgt_app"}}
  end

  defp seed(target, relative, contents) do
    file = Path.join(target, relative)
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, contents)
    file
  end
end
