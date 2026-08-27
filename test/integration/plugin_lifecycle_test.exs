defmodule Capstone.Integration.PluginLifecycleTest do
  @moduledoc """
  Exercises the real registry seeded in priv/plugins/ end to end: a project
  generated with plugins: [:cache] carries the cache plugin's files from the
  first `mix capstone.new`, and a second project generated with no plugins
  gains them afterward via `mix capstone.update`.

  Both projects use `base: :api`, not `:otp`: `Capstone.Plugin.Install` reads
  `target.exs` back through `Capstone.Config` (Apply -> Record, and
  `Capstone.Update.run/2` itself), and `Capstone.Config`'s `@valid_bases` has
  no `:otp` value. A project whose base is `:otp` writes and generates fine,
  but fails the read-back the moment any plugin — applied at generation time
  or via a later update — needs it, so every test here that touches a plugin
  uses `:api`, exactly as `test/integration/target_project_test.exs`'s own
  plugin-application test does.

  `Options.name` is also the value `Capstone.Config.Project` writes and
  re-validates as `project.name` — it must be a bare lowercase OTP app name
  (`Capstone.Config.Project`'s `@name_pattern`), never a path. So each project
  is generated with a bare name from inside its own tmp dir, via
  `File.cd!/2`, the same way `target_project_test.exs`'s tests do — never by
  handing `Options.name` a full path.

  Fixtures live under `System.tmp_dir!()` rather than ExUnit's `@tag :tmp_dir`
  (which nests them under this repo's own `tmp/`, i.e. under `File.cwd!()`).
  The `:cache` plugin patches `lib/APP.ex`, leaving a genuine unresolved
  `:manual` region a human is meant to resolve by hand — correct plugin
  behavior, but `capstone.check_test.exs`'s "defaults to the current
  directory" test scans the whole cwd recursively for exactly that, and would
  sweep up these leftover fixtures if they lived inside the repo tree. Same
  convention as `test/integration/target_project_test.exs`.
  """

  use ExUnit.Case, async: false

  alias Capstone.New.Bootstrap
  alias Capstone.New.Options
  alias Capstone.Plugin.Registry
  alias Capstone.Update

  # `Mix.Task.run/2` runs a task at most once per node. Both tests here go
  # through Bootstrap.defaults()'s REAL generator effect (Mix.Task.run/2
  # itself, not a stand-in that skips the run-once bookkeeping the way
  # target_project_test.exs's own generate!/2 helper does), and both drive
  # `base: :api`, i.e. both call `phx.new` — so without reenabling it here,
  # the second test's call becomes a silent no-op and generates nothing.
  #
  # Mix.Local.append_archives/0 restores the archives an earlier toolchain
  # test's `deps.compile` pruned off the code path (see
  # Capstone.New.Bootstrap's moduledoc) — without it `Mix.Task.get("phx.new")`
  # can return nil even though phx_new is installed on disk.
  setup do
    Mix.Local.append_archives()
    Mix.Task.reenable("new")
    Mix.Task.reenable("phx.new")

    dir = Path.join(System.tmp_dir!(), "plugin-lifecycle-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, tmp_dir: dir}
  end

  @tag :toolchain
  test "mix capstone.new applies plugins: [:cache] from target.exs", %{tmp_dir: tmp} do
    capstone_path = File.cwd!()
    name = "with_cache"

    opts = %Options{
      name: name,
      app: :with_cache,
      module: WithCache,
      base: :api,
      github_org: "acme",
      capstone: {:path, capstone_path},
      plugins: [:cache]
    }

    File.cd!(tmp, fn -> assert :ok = Bootstrap.run(opts, Bootstrap.defaults()) end)

    project = Path.join(tmp, name)
    assert File.exists?(Path.join(project, "target.exs"))
    # priv/meta/meta_cache/manifest.exs records "lib/APP/cache.ex" as
    # :sole_owner; APP resolves to the target's own `app:` (Capstone.Template),
    # i.e. "with_cache" here.
    assert File.exists?(Path.join(project, "lib/with_cache/cache.ex"))
  end

  @tag :toolchain
  test "mix capstone.update applies a plugin added to an existing project's target.exs", %{
    tmp_dir: tmp
  } do
    capstone_path = File.cwd!()
    name = "no_cache_yet"

    opts = %Options{
      name: name,
      app: :no_cache_yet,
      module: NoCacheYet,
      base: :api,
      github_org: "acme",
      capstone: {:path, capstone_path},
      plugins: []
    }

    File.cd!(tmp, fn -> assert :ok = Bootstrap.run(opts, Bootstrap.defaults()) end)

    project = Path.join(tmp, name)
    target_exs = Path.join(project, "target.exs")

    File.write!(
      target_exs,
      String.replace(File.read!(target_exs), "plugins: []", "plugins: [:cache]")
    )

    assert {:ok, [:cache]} = Update.run(project, Registry.default_dir())
    assert File.exists?(Path.join(project, "lib/no_cache_yet/cache.ex"))
  end
end
