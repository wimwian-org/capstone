defmodule Capstone.Integration.PluginLifecycleTest do
  @moduledoc """
  Exercises the real registry seeded in priv/plugins/ end to end: a project
  generated with plugins: [:openapi] carries the openapi plugin's files from
  the first `mix capstone.new`, and a second project generated with no plugins
  gains them afterward via `mix capstone.update`.

  Both projects use `base: :api`, not `:otp`: `Capstone.Plugin.Install` reads
  `target.exs` back through `Capstone.Config` (Apply -> Record, and
  `Capstone.Update.run/2` itself), and `Capstone.Config`'s `@valid_bases` has
  no `:otp` value. A project whose base is `:otp` writes and generates fine,
  but fails the read-back the moment any plugin — applied at generation time
  or via a later update — needs it, so every test here that touches a plugin
  uses `:api`, exactly as `test/integration/target_project_test.exs`'s own
  plugin-application test does.

  ## Why every test here checks for an absent marker AND a real `mix compile`

  `:cache` was originally derived against the `:otp` baseline, whose
  `:manual` anchor is text (`lib/new_otp_app.ex`'s "hello world" moduledoc)
  that exists only there — `:otp` is not a base `mix capstone.new` can
  produce (`Capstone.Config`'s `@valid_bases` has no `:otp` value), so
  against every base the generator actually produces the anchor never
  matched and `Capstone.Plugin.Apply.place/6` fell back to an unresolved
  conflict region at the end of a file that then would not compile. `:cache`
  is now derived against `:api` instead (`priv/meta/cache_component`,
  matching `priv/baselines.exs`'s `derived_from: :api`), whose own moduledoc
  supplies a real anchor. The failure mode this fixed was SILENT — apply
  returns `:ok`, writes every `:sole_owner` file, and leaves the `:manual`
  hunk unresolved — so `File.exists?/1` on a `:sole_owner` file alone would
  never have noticed it, which is why every test below also asserts on both
  an absent conflict marker and a real `mix compile`.

  `Options.name` is also the value `Capstone.Config.Project` writes and
  re-validates as `project.name` — it must be a bare lowercase OTP app name
  (`Capstone.Config.Project`'s `@name_pattern`), never a path. So each project
  is generated with a bare name from inside its own tmp dir, via
  `File.cd!/2`, the same way `target_project_test.exs`'s tests do — never by
  handing `Options.name` a full path.

  Fixtures live under `System.tmp_dir!()` rather than ExUnit's `@tag :tmp_dir`
  (which nests them under this repo's own `tmp/`, i.e. under `File.cwd!()`).
  `capstone.check_test.exs`'s "defaults to the current directory" test scans
  the whole cwd recursively for conflict markers and would sweep up these
  leftover fixtures if they lived inside the repo tree. Same convention as
  `test/integration/target_project_test.exs`.
  """

  use ExUnit.Case, async: false

  alias Capstone.New.Bootstrap
  alias Capstone.New.Options
  alias Capstone.New.Shell
  alias Capstone.Plugin.Apply
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
  test "mix capstone.new applies plugins: [:openapi] from target.exs", %{tmp_dir: tmp} do
    capstone_path = File.cwd!()
    name = "with_openapi"

    opts = %Options{
      name: name,
      app: :with_openapi,
      module: WithOpenapi,
      base: :api,
      github_org: "acme",
      capstone: {:path, capstone_path},
      plugins: [:openapi]
    }

    File.cd!(tmp, fn -> assert :ok = Bootstrap.run(opts, Bootstrap.defaults()) end)

    project = Path.join(tmp, name)
    assert File.exists?(Path.join(project, "target.exs"))
    # priv/meta/meta_openapi/manifest.exs records "lib/APP_web/api_spec.ex" as
    # :sole_owner; APP resolves to the target's own `app:` (Capstone.Template),
    # i.e. "with_openapi" here.
    assert File.exists?(Path.join(project, "lib/with_openapi_web/api_spec.ex"))

    router = "lib/#{name}_web/router.ex"
    assert_placed_not_marked(project, router, "OpenApiSpex")
    # Bootstrap already ran deps.get and deps.compile, open_api_spex included,
    # so this is the app's own sources against the deps the plugin declared.
    Shell.cmd!(["compile"], project)
  end

  @tag :toolchain
  test "mix capstone.update applies a plugin added to an existing project's target.exs", %{
    tmp_dir: tmp
  } do
    capstone_path = File.cwd!()
    name = "no_openapi_yet"

    opts = %Options{
      name: name,
      app: :no_openapi_yet,
      module: NoOpenapiYet,
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
      String.replace(File.read!(target_exs), "plugins: []", "plugins: [:openapi]")
    )

    assert {:ok, [:openapi]} = Update.run(project, Registry.default_dir())
    assert File.exists?(Path.join(project, "lib/no_openapi_yet_web/api_spec.ex"))

    router = "lib/no_openapi_yet_web/router.ex"
    assert_placed_not_marked(project, router, "OpenApiSpex")
    # The plugin added {:open_api_spex, ...} to a mix.exs whose deps were
    # already fetched, so this path needs its own deps.get before compiling.
    Shell.cmd!(["deps.get"], project)
    Shell.cmd!(["compile"], project)
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
    # priv/meta/meta_cache/manifest.exs records "lib/APP/cache.ex" and
    # "lib/APP/cache/store.ex" as :sole_owner; APP resolves to the target's
    # own `app:` (Capstone.Template), i.e. "with_cache" here.
    assert File.exists?(Path.join(project, "lib/with_cache/cache.ex"))
    assert File.exists?(Path.join(project, "lib/with_cache/cache/store.ex"))

    top_level = "lib/#{name}.ex"
    assert_placed_not_marked(project, top_level, "defdelegate fetch")
    # Bootstrap already ran deps.get and deps.compile, nebulex included, so
    # this is the app's own sources against the deps the plugin declared.
    Shell.cmd!(["compile"], project)

    smoke_test = """
    {:ok, _} = Application.ensure_all_started(:with_cache)
    calls = :counters.new(1, [])
    compute = fn -> :counters.add(calls, 1, 1); :counters.get(calls, 1) end

    1 = WithCache.fetch("k", compute)
    1 = WithCache.fetch("k", compute)
    IO.puts("fetch/2 caches: PASS")

    2 = WithCache.fetch("ttl-k", 50, compute)
    Process.sleep(100)
    3 = WithCache.fetch("ttl-k", 50, compute)
    IO.puts("fetch/3 expires: PASS")
    """

    output = Shell.cmd!(["run", "-e", smoke_test], project)
    assert output =~ "fetch/2 caches: PASS"
    assert output =~ "fetch/3 expires: PASS"
  end

  @tag :toolchain
  test "mix capstone.new applies plugins: [:cqrs] from target.exs", %{tmp_dir: tmp} do
    capstone_path = File.cwd!()
    name = "with_cqrs"

    opts = %Options{
      name: name,
      app: :with_cqrs,
      module: WithCqrs,
      base: :api,
      github_org: "acme",
      capstone: {:path, capstone_path},
      plugins: [:cqrs]
    }

    File.cd!(tmp, fn -> assert :ok = Bootstrap.run(opts, Bootstrap.defaults()) end)

    project = Path.join(tmp, name)
    assert File.exists?(Path.join(project, "target.exs"))
    assert File.exists?(Path.join(project, "lib/with_cqrs/cqrs/dispatcher.ex"))
    assert File.exists?(Path.join(project, "lib/with_cqrs/cqrs/reservation.ex"))
    assert File.exists?(Path.join(project, "lib/with_cqrs/event_store.ex"))

    application = File.read!(Path.join(project, "lib/with_cqrs/application.ex"))
    assert application =~ "WithCqrs.CQRS.App"
    assert application =~ "WithCqrs.CQRS.Cache"

    Shell.cmd!(["compile"], project)
  end

  # The design spec's "Composability with :cache" section claims :cqrs and
  # :cache can both be applied to one project without conflict — this is
  # the only test that actually applies both together and proves it.
  @tag :toolchain
  @tag timeout: :timer.minutes(3)
  test "mix capstone.new applies plugins: [:cache, :cqrs] together without conflict", %{
    tmp_dir: tmp
  } do
    capstone_path = File.cwd!()
    name = "with_cache_and_cqrs"

    opts = %Options{
      name: name,
      app: :with_cache_and_cqrs,
      module: WithCacheAndCqrs,
      base: :api,
      github_org: "acme",
      capstone: {:path, capstone_path},
      plugins: [:cache, :cqrs]
    }

    File.cd!(tmp, fn -> assert :ok = Bootstrap.run(opts, Bootstrap.defaults()) end)

    project = Path.join(tmp, name)
    assert File.exists?(Path.join(project, "lib/with_cache_and_cqrs/cache.ex"))
    assert File.exists?(Path.join(project, "lib/with_cache_and_cqrs/cqrs/dispatcher.ex"))

    application = File.read!(Path.join(project, "lib/with_cache_and_cqrs/application.ex"))
    assert application =~ "WithCacheAndCqrs.Cache.Store"
    assert application =~ "WithCacheAndCqrs.CQRS.App"
    assert application =~ "WithCacheAndCqrs.CQRS.Cache"

    config = File.read!(Path.join(project, "config/config.exs"))
    assert config =~ "WithCacheAndCqrs.Cache.Store"
    assert config =~ "WithCacheAndCqrs.EventStore"
    assert config =~ "WithCacheAndCqrs.CQRS.App"

    Shell.cmd!(["compile"], project)

    # config/test.exs already overrides CQRS.App to the InMemory adapter.
    # `mix test` (unlike `mix run`) runs under :test env via Mix's own
    # preferred_cli_env regardless of Shell's MIX_ENV-scrubbing for child
    # processes, so this genuinely exercises the InMemory-backed
    # supervision tree — including the real, Nebulex-backed :cache Store —
    # without needing a real Postgres-backed event store. mix test itself
    # fails loudly (Shell.cmd! raises on non-zero exit) if the application
    # can't start during test setup, which is exactly what this proves.
    Shell.cmd!(["test"], project)
  end

  @tag :toolchain
  @tag timeout: :timer.minutes(3)
  test "mix capstone.new applies plugins: [:grpc] from target.exs", %{tmp_dir: tmp} do
    capstone_path = File.cwd!()
    name = "with_grpc"

    opts = %Options{
      name: name,
      app: :with_grpc,
      module: WithGrpc,
      base: :api,
      github_org: "acme",
      capstone: {:path, capstone_path},
      plugins: [:grpc]
    }

    File.cd!(tmp, fn -> assert :ok = Bootstrap.run(opts, Bootstrap.defaults()) end)

    project = Path.join(tmp, name)
    assert File.exists?(Path.join(project, "target.exs"))
    assert File.exists?(Path.join(project, "lib/with_grpc/grpc/endpoint.ex"))
    assert File.exists?(Path.join(project, "lib/with_grpc/grpc/client.ex"))
    assert File.exists?(Path.join(project, "priv/cert/grpc_selfsigned.pem"))

    application = "lib/#{name}/application.ex"
    assert_placed_not_marked(project, application, "WithGrpc.GRPC.Endpoint")

    Shell.cmd!(["compile"], project)

    # config/test.exs is inherited unchanged from baseline_api (this plugin
    # has no InMemory-vs-real split the way :cqrs does — the server either
    # runs or doesn't, and the committed test cert is real either way), so
    # `mix test` genuinely starts the whole supervision tree, including the
    # real, TLS-wrapped GRPC.Server.Supervisor, under real :test env — per
    # this branch's own hard-won lesson (:cqrs's Task 9), `mix test` (not
    # `mix run -e`) is the only way Shell.cmd! reliably reaches :test env.
    Shell.cmd!(["test"], project)
  end

  @tag :toolchain
  @tag timeout: :timer.minutes(3)
  test "mix capstone.new applies plugins: [:openbao] from target.exs", %{tmp_dir: tmp} do
    capstone_path = File.cwd!()
    name = "with_openbao"

    opts = %Options{
      name: name,
      app: :with_openbao,
      module: WithOpenbao,
      base: :api,
      github_org: "acme",
      capstone: {:path, capstone_path},
      plugins: [:openbao]
    }

    File.cd!(tmp, fn -> assert :ok = Bootstrap.run(opts, Bootstrap.defaults()) end)

    project = Path.join(tmp, name)
    assert File.exists?(Path.join(project, "target.exs"))
    assert File.exists?(Path.join(project, "compose.yaml"))
    assert File.exists?(Path.join(project, "lib/with_openbao/vault.ex"))

    assert_placed_not_marked(project, "config/runtime.exs", "WithOpenbao.Vault")
    assert_placed_not_marked(project, "config/dev.exs", "WithOpenbao.Vault")
    assert_placed_not_marked(project, "config/test.exs", "WithOpenbao.Vault")

    # Bootstrap already ran deps.get and deps.compile; req is already a
    # baseline dependency, so this plugin adds none.
    Shell.cmd!(["compile"], project)

    # No live OpenBao sidecar is started here — vault_test.exs stubs the HTTP
    # transport with Req.Test, so this proves the plugin compiles and passes
    # out of the box without `compose.yaml` ever being brought up.
    Shell.cmd!(["test"], project)
  end

  # The failure mode this guards against is SILENT: apply returns :ok, writes
  # every :sole_owner file, and leaves the :manual hunk in an unresolved
  # conflict region at the end of a file that no longer compiles. So assert on
  # both halves — the hunk landed at its anchor (`relative_file` contains
  # `expected`), and no marker was written anywhere in the generated tree.
  defp assert_placed_not_marked(project, relative_file, expected) do
    assert File.read!(Path.join(project, relative_file)) =~ expected

    marked =
      project
      |> Path.join("**")
      |> Path.wildcard(match_dot: true)
      |> Enum.reject(&(File.dir?(&1) or &1 =~ ~r{/(deps|_build)/}))
      |> Enum.filter(fn file ->
        contents = File.read!(file)
        String.valid?(contents) and String.contains?(contents, Apply.marker_prefix(""))
      end)

    assert marked == []
  end
end
