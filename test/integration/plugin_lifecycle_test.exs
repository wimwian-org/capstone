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
  alias Capstone.Plugin.Package
  alias Capstone.Plugin.Registry
  alias Capstone.Plugin.Remote
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
  @tag timeout: :timer.minutes(5)
  test "mix capstone.new applies plugins: [:web_layer] from target.exs", %{tmp_dir: tmp} do
    # The design spec and this plan's Global Constraints both require a real
    # pnpm/Vite run to gate this test — mirroring Shell.ensure_task_available!/2's
    # loud failure for a missing "mix phx.new" rather than a silent skip, per
    # test_helper.exs's own reasoning: "a machine without the generators
    # reports them as failures rather than as absences."
    if is_nil(System.find_executable("pnpm")) do
      raise "pnpm is not available on PATH — install it (https://pnpm.io/installation) to run " <>
              "this toolchain test's real assets.setup/assets.build steps"
    end

    capstone_path = File.cwd!()
    name = "with_web_layer"

    opts = %Options{
      name: name,
      app: :with_web_layer,
      module: WithWebLayer,
      base: :api,
      github_org: "acme",
      capstone: {:path, capstone_path},
      plugins: [:web_layer]
    }

    File.cd!(tmp, fn -> assert :ok = Bootstrap.run(opts, Bootstrap.defaults()) end)

    project = Path.join(tmp, name)
    assert File.exists?(Path.join(project, "target.exs"))
    assert File.exists?(Path.join(project, "assets/svelte/components/AppShell.svelte"))

    assert File.exists?(
             Path.join(project, "lib/with_web_layer_web/components/core_components.ex")
           )

    assert File.exists?(Path.join(project, "lib/with_web_layer/vite_watcher.ex"))

    # priv/meta/meta_web_layer/manifest.exs's router.ex hunk inserts a
    # :browser pipeline and `import Phoenix.LiveView.Router`, none of which
    # exist in base :api's pristine router.ex (priv/meta/baseline_api's own
    # router.ex has only :api / dev_routes) — so "WithWebLayerWeb.Layouts",
    # rendered from `<%= @module %>Web.Layouts` inside that hunk, only shows
    # up here if the hunk actually landed at its anchor.
    router = "lib/#{name}_web/router.ex"
    assert_placed_not_marked(project, router, "WithWebLayerWeb.Layouts")

    Shell.cmd!(["compile"], project)
    Shell.cmd!(["test"], project)

    # The real toolchain gate this plugin's own plan required but never got:
    # a real "pnpm install" against the shipped pnpm-lock.yaml, and a real
    # Vite build of the Svelte 5 UI it locks against. Neither package.json's
    # validity, the lockfile's resolvability, Svelte compilation, nor the
    # Vite build itself is exercised anywhere else in this suite.
    Shell.cmd!(["assets.setup"], project)
    Shell.cmd!(["assets.build"], project)

    manifest_path = Path.join(project, "priv/static/.vite/manifest.json")
    assert File.regular?(manifest_path)

    manifest = manifest_path |> File.read!() |> :json.decode()

    assert %{"js/app.js" => %{"file" => js_file}, "css/app.css" => %{"file" => css_file}} =
             manifest

    assert File.regular?(Path.join(project, "priv/static/#{js_file}"))
    assert File.regular?(Path.join(project, "priv/static/#{css_file}"))
  end

  @tag :toolchain
  @tag timeout: :timer.minutes(3)
  test "mix capstone.new applies plugins: [:podman, :openbao, :valkey] from target.exs", %{
    tmp_dir: tmp
  } do
    capstone_path = File.cwd!()
    name = "with_sidecars"

    opts = %Options{
      name: name,
      app: :with_sidecars,
      module: WithSidecars,
      base: :api,
      github_org: "acme",
      capstone: {:path, capstone_path},
      plugins: [:podman, :openbao, :valkey]
    }

    {effects, registry} = local_openbao_valkey_effects(capstone_path, tmp)
    File.cd!(tmp, fn -> assert :ok = Bootstrap.run(opts, effects, registry) end)

    project = Path.join(tmp, name)
    assert File.exists?(Path.join(project, "target.exs"))
    assert File.exists?(Path.join(project, "lib/with_sidecars/vault.ex"))
    assert File.exists?(Path.join(project, "lib/with_sidecars/valkey/cache.ex"))

    compose = File.read!(Path.join(project, "compose.yaml"))
    assert compose =~ "openbao:"
    assert compose =~ "valkey:"

    assert_placed_not_marked(project, "config/runtime.exs", "WithSidecars.Vault")
    assert_placed_not_marked(project, "config/runtime.exs", "WithSidecars.Valkey")
    assert_placed_not_marked(project, "config/dev.exs", "WithSidecars.Vault")
    assert_placed_not_marked(project, "config/dev.exs", "WithSidecars.Valkey")
    assert_placed_not_marked(project, "config/test.exs", "WithSidecars.Vault")
    assert_placed_not_marked(project, "config/test.exs", "WithSidecars.Valkey")
    assert_placed_not_marked(project, "lib/with_sidecars/application.ex", "WithSidecars.Valkey")

    # Bootstrap already ran deps.get and deps.compile; req is already a
    # baseline dependency (openbao adds none), redix is valkey's one added dep.
    Shell.cmd!(["compile"], project)

    # No live OpenBao/Valkey sidecar is started here — vault_test.exs stubs
    # the HTTP transport with Req.Test, and valkey_test.exs is tagged
    # :valkey (excluded by default, since Redix has no equivalent stub) — so
    # this proves the plugins compile and pass out of the box without
    # `compose.yaml` ever being brought up.
    Shell.cmd!(["test"], project)

    application_ex = File.read!(Path.join(project, "lib/with_sidecars/application.ex"))
    assert application_ex =~ ~r/children = \[\s*\n\s*WithSidecars\.Vault\.Auth,/
    assert application_ex =~ "WithSidecars.Valkey.Cache.L1"
    assert application_ex =~ "WithSidecars.Valkey.Breaker"
    assert application_ex =~ "WithSidecars.Valkey.Invalidator"
  end

  @tag :toolchain
  @tag timeout: :timer.minutes(3)
  test "an approle-misconfigured boot fails mix run outright (the boot gate)", %{tmp_dir: tmp} do
    capstone_path = File.cwd!()
    name = "with_bad_approle"

    opts = %Options{
      name: name,
      app: :with_bad_approle,
      module: WithBadApprole,
      base: :api,
      github_org: "acme",
      capstone: {:path, capstone_path},
      plugins: [:podman, :openbao]
    }

    {effects, registry} = local_openbao_valkey_effects(capstone_path, tmp)
    File.cd!(tmp, fn -> assert :ok = Bootstrap.run(opts, effects, registry) end)

    project = Path.join(tmp, name)

    runtime_exs = Path.join(project, "config/runtime.exs")

    File.write!(
      runtime_exs,
      String.replace(
        File.read!(runtime_exs),
        ~s[openbao_method = System.get_env("OPENBAO_METHOD", "token") |> String.to_existing_atom()],
        ~s[openbao_method = :approle]
      )
    )

    {output, exit_code} =
      System.cmd(
        "mix",
        ["run", "-e", "IO.puts(:booted)"],
        cd: project,
        env: [
          {"MIX_ENV", "prod"},
          {"OPENBAO_ADDR", "http://localhost:8200"},
          {"OPENBAO_ROLE_ID", "does-not-exist"},
          {"OPENBAO_SECRET_ID", "does-not-exist"},
          {"SECRET_KEY_BASE", String.duplicate("a", 64)},
          {"DATABASE_URL", "ecto://postgres:postgres@localhost/nonexistent"}
        ],
        stderr_to_stdout: true
      )

    refute exit_code == 0
    refute output =~ "booted"
  end

  @tag :toolchain
  @tag timeout: :timer.minutes(3)
  test "mix capstone.new applies plugins: [:podman, :openapi, :nginx] from target.exs", %{
    tmp_dir: tmp
  } do
    capstone_path = File.cwd!()
    name = "with_nginx"

    opts = %Options{
      name: name,
      app: :with_nginx,
      module: WithNginx,
      base: :api,
      github_org: "acme",
      capstone: {:path, capstone_path},
      plugins: [:podman, :openapi, :nginx]
    }

    File.cd!(tmp, fn -> assert :ok = Bootstrap.run(opts, Bootstrap.defaults()) end)

    project = Path.join(tmp, name)
    assert File.exists?(Path.join(project, "nginx.conf"))

    compose = File.read!(Path.join(project, "compose.yaml"))
    assert compose =~ "nginx:"
    assert compose =~ ~s(- "${APP_PORT:-4000}:80")
    refute compose =~ ~s(- "${APP_PORT:-4000}:4000")

    Shell.cmd!(["compile"], project)
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

  # `Capstone.Plugin.Remote` downloads real archives from this repository's
  # published GitHub releases (see its moduledoc) — a source that is
  # necessarily behind an unreleased branch's own `priv/meta/meta_<name>`.
  # `:openbao` and `:valkey` are exactly what this plan rewrote, so a real
  # download would silently install the last-published (pre-rewrite)
  # archive instead of this checkout's own plugin code — the same
  # registry-dir + no-op-`sync` pattern `target_project_test.exs`'s "applies
  # a real registry plugin" test already uses for an unpublished fixture
  # plugin. `:podman` is untouched by this plan, so it still syncs for
  # real, exactly as the rest of this file's tests do.
  defp local_openbao_valkey_effects(capstone_path, tmp) do
    registry = Path.join(tmp, "registry-#{System.unique_integer([:positive])}")

    for type <- [:openbao, :valkey] do
      {:ok, _path} =
        Package.run(type, Path.join(capstone_path, "priv/meta/meta_#{type}"), registry)
    end

    effects = %{
      Bootstrap.defaults()
      | sync: fn
          type, _dir when type in [:openbao, :valkey] -> :ok
          type, dir -> Remote.sync!(type, dir)
        end
    }

    {effects, registry}
  end
end
