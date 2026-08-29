# Container sidecars — `:podman`, `:openbao`, `:valkey`, `:nginx` — design

Date: 2026-08-29
Status: implemented (this spec documents what was built, written alongside
implementation rather than strictly before it — see "Provenance")

## Purpose

Four new first-party plugins, all `derived_from` a shared foundation, giving a
generated project optional container sidecars without any of them fighting
over `compose.yaml`:

- **`:podman`** — the foundation. Adds `compose.yaml` with `db` (Postgres) and
  `app` (the project itself) services. Nothing else derives straight from
  `:api` for its compose needs any more; everything below derives from
  `:api_podman` (`:api` + `:podman`, composed the same way `:web` is spec'd to
  be `:api` + `web_layer` in
  `docs/superpowers/specs/2026-08-29-web-plugin-design.md`).
- **`:openbao`** — an OpenBao (Vault-compatible) secrets sidecar. Secrets
  only: general KV storage is explicitly `:valkey`'s job, not this plugin's.
- **`:valkey`** — the default KV platform, a thin Redix client against a
  Valkey (Redis-protocol) sidecar. No Nebulex, no cache-abstraction layer —
  a direct driver, deliberately mirroring `:openbao`'s own "no framework,
  just the protocol client" minimalism.
- **`:nginx`** — reverse-proxies the Phoenix app's own HTTP endpoints only
  (`/api`, `/openapi`, `/docs`) and takes over the app's host port. Once
  applied, nginx is the only way to reach the app from outside the compose
  network. It does not front `:openbao` or `:valkey` — those keep their own
  direct sidecar access, unchanged by whether `:nginx` is applied.

## Provenance

Supersedes `docs/superpowers/specs/2026-08-29-openbao-plugin-design.md` and
`docs/superpowers/plans/2026-08-29-openbao-plugin.md`, both left in place as
historical record of `:openbao`'s first draft (`compose.yaml` as
`:sole_owner`, `derived_from: :api` directly, production framed as "points at
an externally operated cluster" rather than "also runs the sidecar pattern").
That draft's own "Known limitation" section named the exact problem this spec
resolves — quoted here because it states the constraint precisely:

> `:sole_owner` writes unconditionally... `:openapi` and `:openbao` therefore
> cannot both be applied to one project today without one silently discarding
> the other's `compose.yaml`... nothing yet provides a `:seed`-mode base
> `compose.yaml` scaffold for sidecars to append into.

Investigating that gap found `:seed` is declared in
`Capstone.Plugin.Behavior`'s mode enum and moduledoc but **has no clause in
`Capstone.Plugin.Apply.entry/4` at all** — calling it would raise a
`FunctionClauseError`. It is not an unfinished primitive worth finishing; nothing
in `Capstone.Plugin.Derive` can ever emit it either (a brand-new path is
always classified `:sole_owner`; `:contributes` requires the path to already
be a *modified*, not *added*, file — `Capstone.Plugin.Derive.entries/2` and
`Capstone.Plugin.Classify.bucket/2`). The fix that actually works within the
existing, already-tested derive machinery is upstream of `:seed` entirely:
give `compose.yaml` a home in a **baseline** every sidecar derives from, so
each sidecar's own compose addition is a *modification* to an existing file
— which `Classify.bucket/2` already routes to `:contributes` automatically
for any non-Elixir extension, with zero new `Apply`/`Derive` code.

## The `:api_podman` baseline

```
priv/meta/podman_component/        # api + compose.yaml (db, app), :sole_owner
  → mix capstone.plugin.derive podman → priv/meta/meta_podman/
priv/baselines.exs: api_podman: %{derived_from: :api, plugin: :podman, path: "priv/meta/baseline_api_podman"}
  → mix capstone.baseline.compose api_podman → priv/meta/baseline_api_podman/
```

`openapi`, `openbao`, `valkey`, and `nginx` all set `derived_from: :api_podman`
(not `:api`). Each raw component's own `compose.yaml` is the foundation's
content plus, where applicable, one appended service block — verified by
`mix capstone.plugin.derive` classifying every one of them as `{"compose.yaml",
:contributes, key: ...}` with no `:manual` fallback anywhere.

`openapi_component`'s own `compose.yaml` (previously the *source* of the
`db`+`app` definitions, before this work) is now byte-identical to
`baseline_api_podman`'s — so `openapi`'s derived manifest drops the
`compose.yaml` entry entirely; that file comes from `:podman` now, and
`:openapi` no longer touches it. This is not a regression: nothing in
`:openapi`'s own purpose (schemas, health checks, the OpenAPI spec route) was
ever about compose plumbing.

`services:` must stay the last top-level key in every raw component's
`compose.yaml`. A `:contributes` append is a plain string concatenation at
end-of-file (`Capstone.Plugin.Apply.place_contribution/3`, the `:append`
clause) — a `volumes:`/`networks:` key added after `services:` in one
sidecar's raw tree would land nested under whichever sidecar's block happens
to be applied last, not at the top level. None of the four plugins add such a
key; this constraint is why, documented in `podman_component/compose.yaml`'s
own trailing comment for the next person who adds a fifth sidecar.

## `:openbao`

Unchanged from the superseded spec's own design in substance — image
(`docker.io/openbao/openbao:latest`, Alpine-based upstream), `-dev` mode with
a fixed root token, `NewApiApp.Vault`'s plain-`Req` KV v2 client, and
`config/runtime.exs`'s `if config_env() == :prod do` guard requiring
`OPENBAO_TOKEN` from the environment with no default. What changed:

- `derived_from: :api_podman`, and `compose.yaml`'s entry is `:contributes`
  (`key: :openbao_compose`) instead of `:sole_owner`.
- **Production also runs the sidecar pattern**, not "a separately operated
  OpenBao deployment." `config/runtime.exs`'s existing
  `base_url: System.get_env("OPENBAO_ADDR", "http://localhost:8200")` default
  was, on inspection, already sidecar-shaped (a real external cluster
  wouldn't sanely default to `localhost`) — only the surrounding prose (in
  `compose.yaml`'s comment and the old spec) mischaracterized it. No code
  changed here; the comment now says the same image runs as this service's
  sidecar in prod too, an OCI-compliant container placed beside the app by
  whatever orchestrator runs it there — not this compose file, which is a
  test/dev tool. `OPENBAO_TOKEN` still has no default anywhere outside dev/test
  — that part of the design was already correct and is unchanged.

## `:valkey`

The default KV platform. Deliberately **not** Nebulex, despite
`docs/guides/building-a-plugin.md`'s own canonical `Behavior` example using
exactly this scenario (`MyOrg.Valkey`, `{:nebulex, "~> 3.0"}`,
`lib/APP/cache.ex`) — that example predates this plugin and is illustrative
only. Explicit direction: OpenBao's KV v2 API is not to be used as a
general-purpose store (secrets only); Valkey is the one KV platform, via
Redix directly, mirroring `:openbao`'s own "plain protocol client, no
framework" choice rather than layering a cache abstraction on top.

- `docker.io/valkey/valkey:alpine` — a genuine floating tag (confirmed via
  Docker Hub, not assumed), always the newest Alpine build, mirroring
  `:openbao`'s `:latest` mentioned in the superseded spec.
- `NewApiApp.Valkey` — a ~20-line `Redix.child_spec/1`-based module
  (`get/1`, `set/3`), permanently in the supervision tree
  (`lib/APP/application.ex`, `:contributes` with `child:`, auto-detected by
  `Capstone.Plugin.Derive.added_child/2`'s replay mechanism — no manifest
  hand-editing).
- Empirically verified before writing any of this: `Nebulex.Adapters.Redis`
  (and, more directly relevant, plain `Redix`) tolerate the sidecar being
  *absent* at application boot — `Supervisor.start_link/2` succeeds, the
  process stays alive, and an operation against an unreachable server returns
  `{:error, %Redix.ConnectionError{reason: :closed}}` rather than crashing.
  This is why `NewApiApp.Valkey` can be a permanent, unconditional supervision
  child: `mix test`'s default run boots the whole app fine with no live
  sidecar, exactly like every other plugin's committed test.
- `openbao` and `valkey` both publish their sidecar port bound to loopback
  only (`127.0.0.1:8200:8200`, `127.0.0.1:6379:6379`), not all host
  interfaces — caught by an automated security review mid-implementation:
  the unqualified `"6379:6379"` form binds every interface, so on a shared
  network Valkey (no auth at all) would have been reachable by anyone who
  could reach the host, not just this machine's own `mix test`/`mix
  phx.server`. Loopback binding doesn't affect inter-container reachability
  (other compose services still resolve `valkey`/`openbao` by service name
  over the compose network regardless) — only host-level access is
  restricted. `nginx`'s own port is deliberately NOT loopback-restricted: it
  is the intended public-facing ingress, matching the app's own port's
  pre-existing (also non-loopback) publish behavior before `:nginx` existed.
- `test/APP/valkey_test.exs` is `@moduletag :valkey`, excluded by default via
  `ExUnit.configure(exclude: [valkey: true])` appended to
  `test/test_helper.exs` (a pure addition — a new line, not a rewrite of the
  existing `ExUnit.start()` call, which would have forced the whole file to
  `:manual` per `Capstone.Plugin.Derive.file_mode/3`'s "any removal makes the
  whole file `:manual`" rule). Redix has no `Req.Test`-equivalent stub
  tooling, so unlike `:openbao`'s fully-mocked default test, this one
  genuinely needs the sidecar — hence the opt-in tag rather than a mock.
- Same "prod also runs the sidecar" framing as `:openbao`: `config/runtime.exs`
  defaults `VALKEY_HOST`/`VALKEY_PORT` to `localhost`/`6379`, same as
  dev/test, since Valkey needs no secret token to protect (unlike OpenBao) —
  there was never an asymmetry to fix here beyond the comment wording.
- **Deps ordering pitfall, hit and fixed during this work**: `Capstone.Plugin.Apply.add_deps/2`
  reverses the manifest's `deps:` list before prepending each one — meaning a
  new dep must be recorded (and therefore written, in the raw component's own
  `mix.exs`) at the *front* of the deps list, not the end, or a round-trip
  apply reproduces a different dep order than the raw component's actual
  `mix.exs` and the byte-for-byte round-trip test fails. This is the exact
  defect class commit `a02a106` ("prepend grpc_component's deps to match
  Apply's convention") already fixed once; `valkey_component/mix.exs` was
  initially written wrong the same way and corrected the same way.

## `:nginx`

Reverse-proxies **only** the Phoenix app's own HTTP endpoints — `/api/` →
`app:4000/api/`, `/openapi` → `app:4000/api/v1/openapi` (the raw OpenAPI 3
JSON `:openapi`'s router serves), `/docs/` → `app:4000/api/v1/docs/` (its
Swagger UI). Deliberately does **not** front `:openbao` or `:valkey` — both
keep their own compose-published ports exactly as `:openbao`/`:valkey`
already define them, whether or not `:nginx` is applied to the same project.

`:valkey` speaks the raw Redis wire protocol, not HTTP — a `/valkey` URL path
cannot reverse-proxy it (nginx's `location` blocks operate on parsed HTTP
requests; TCP-level proxying needs a separate `stream {}` block and its own
port, not a path under the same HTTP server). This was raised and the scope
was narrowed to HTTP-only proxying rather than building a mismatched design;
it is not implemented here.

Takes over the app's own former host port: `podman_component/compose.yaml`'s
`app:` service published `${APP_PORT:-4000}:4000` before `:nginx` existed;
once `:nginx` is applied, `app` publishes nothing (reachable only by other
compose services, via its service name) and `nginx` publishes
`${APP_PORT:-4000}:80` instead — the same external port number and env var,
so nothing changes for anyone hitting `localhost:4000` from outside, whether
or not they knew nginx was now in front.

Verified live (not just `podman-compose config` syntax-checked): a real
`nginx:alpine` container with this exact `nginx.conf`, proxying to a
stand-in backend on the same podman network aliased `app`, correctly rewrites
all three paths (`/api/v1/health` → `GOT: /api/v1/health`, `/openapi` →
`GOT: /api/v1/openapi`, `/docs/` → `GOT: /api/v1/docs/`) and 404s anything
else rather than falling through.

## Composability

All four plugins derive from `:api_podman` (or, for `:podman` itself, `:api`)
and none claim the same file `:sole_owner` except each other's genuinely
distinct new files (`lib/APP/vault.ex`, `lib/APP/valkey.ex`, `nginx.conf`).
`compose.yaml` is `:contributes` for `openapi`, `openbao`, `valkey`, and
`nginx` alike, each with its own key — verified for real:
`Capstone.Plugin.Apply.run/3` applied for `:podman` → `:openbao` → `:valkey`
→ `:openapi` → `:nginx`, in that order, onto one scratch project produces a
single `compose.yaml` with all five services (`db`, `app`, `openbao`,
`valkey`, `nginx`) correctly nested, parses with `podman-compose config`, and
the generated project compiles with `--warnings-as-errors` and passes
`mix test` (default tags; `valkey`-tagged tests excluded).

## Out of scope

- **`app: build: context: .` has no `Dockerfile` anywhere in `:api`,
  `:api_podman`, or `:openapi`.** Pre-existing gap, not introduced or fixed
  here — `openapi_component`'s original `compose.yaml` already referenced
  this build context before any of this work started. `podman-compose up app`
  would already have failed to build on a clean checkout of the prior state.
  Flagged, not fixed: building a real release Dockerfile for the bare `:api`
  base is a separate, larger piece of work (`:prod_image_api` already has one,
  scoped to *its own* derived tree, not the bare base).
- **True network isolation of sidecars.** `:nginx` controls *host port
  publishing* only. Any other container already on the same compose network
  can still reach `openbao:8200`/`valkey:6379` directly by service name,
  compose-network membership being what it is — `:nginx` was asked to be
  "the only way to reach the app," which this satisfies, not a network
  policy enforcing that same restriction on every other service.
- **A capability solver, or wiring `container: [sidecars: [...]]` to
  actually select these plugins.** Same status as the superseded spec left
  it: `Capstone.Config.Container.Sidecars` is validated but inert; nothing
  reads it to decide which plugins to apply. A user gets these sidecars by
  listing `plugins: [:podman, :openbao, :valkey, :nginx]` explicitly.
- AppRole/Kubernetes auth, TLS, auto-unseal, or a Valkey password — all
  orchestrator/operator concerns for wherever the real sidecar runs in
  production, orthogonal to what the generated project's own code needs.

## Verification notes (empirical checks made during this work)

- `podman-compose config` (real binary, not hand-inspection) accepts the
  composed 5-service `compose.yaml` and resolves every `${VAR:-default}`
  correctly.
- A live OpenBao sidecar (`podman-compose up -d openbao`) reports healthy on
  the first check; a KV v2 write then read round-trips through its HTTP API
  with the fixed dev token, matching `NewApiApp.Vault.read_secret/2`'s
  expected `data.data` response shape exactly.
- `Redix`/`Nebulex.Adapters.Redis` both tolerate a missing server at
  application boot (own probe project, `mix run -e`) — the supervision tree
  starts, the process stays alive, and a command against it returns a
  `Redix.ConnectionError` rather than crashing.
- A generated scratch project with `plugins: [:podman, :openbao, :valkey,
  :openapi, :nginx]` compiles with `--warnings-as-errors` and `mix test`
  passes (default tags) with no live sidecars running at all.
- Live nginx proxy check against a stand-in backend, described under
  `:nginx` above.
- Full repo gate after all of the above: `mix format --check-formatted`,
  `mix test` (567 passed, 17 excluded), `mix credo --strict` (no issues),
  `mix dialyzer` (passed), `mix doctor` (100% doc/moduledoc coverage, no
  regression from the pre-existing 95.2% spec coverage), `mix coveralls`
  (100%). `mix sobelow`'s pre-existing low-confidence findings are in files
  untouched by this work (confirmed via `git status`) and are not a
  regression.
