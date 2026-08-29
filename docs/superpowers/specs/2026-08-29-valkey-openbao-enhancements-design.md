# `:valkey`/`:openbao` production-readiness enhancements — design

Date: 2026-08-29
Status: approved, pending implementation plan

## Purpose

Both sidecar plugins ship deliberately minimal today — `NewApiApp.Valkey` is a
~20-line `Redix.child_spec/1` wrapper, `NewApiApp.Vault` is a ~30-line
single-function `Req` client reading a static config token. That minimalism
was explicit design intent
(`docs/superpowers/specs/2026-08-29-container-sidecars-design.md`'s "Out of
scope": "AppRole/Kubernetes auth, TLS, auto-unseal, or a Valkey password —
all orchestrator/operator concerns... orthogonal to what the generated
project's own code needs"), not an oversight.

This work reverses that call for both plugins, using
`/Users/pancha/code/elixir/manage_infra` — a separate, mature Elixir
infrastructure-management project — as the reference for what a
production-grade version of each client looks like: a lock-free circuit
breaker and multilevel cache in front of Valkey, and a real login/lease-renewal
auth flow with a fail-closed boot gate in front of OpenBao. Both patterns are
adapted from `manage_infra`'s `ManageInfra.Cache.Breaker`
(`lib/manage_infra/cache/breaker.ex`) and `ManageInfra.Crypto.Auth`
(`lib/manage_infra/crypto/auth.ex`) respectively — cited throughout below.

There are no consumers of either plugin yet (capstone is pre-1.0), so this is
a clean redesign of `NewApiApp.Valkey`/`NewApiApp.Vault`'s shape, not a
migration. Confirmed separately that `mix capstone.update` never re-touches an
already-recorded plugin regardless (`lib/capstone/update.ex:37-46`,
`already_applied/1` at `update.ex:52-60` checks name only, never `version`) —
there is no migration mechanism to design around even if there were consumers.

## Provenance

Revises `docs/superpowers/specs/2026-08-29-container-sidecars-design.md`'s
`:valkey`/`:openbao` sections in place, superseding two specific stated
choices:

> Deliberately **not** Nebulex, despite `docs/guides/building-a-plugin.md`'s
> own canonical `Behavior` example using exactly this scenario... Valkey is
> the one KV platform, via Redix directly, mirroring `:openbao`'s own "plain
> protocol client, no framework" choice.

and the "Out of scope" list's "AppRole/Kubernetes auth... orchestrator/
operator concerns." Both reversals are scoped narrowly (see each plugin's
section below) rather than adopting `manage_infra`'s full surface — Kubernetes
auth, TLS, auto-unseal, HA/Sentinel failover, and OpenBao's Transit/PKI
engines all stay explicitly out of scope; see "Out of scope" below for why
each.

Everything else `docs/superpowers/specs/2026-08-29-container-sidecars-design.md`
established is unchanged: `derived_from: :api_podman`, `compose.yaml` as
`:contributes`, loopback-only port publishing, "production also runs the
sidecar pattern," `:valkey`'s scope staying KV-only (not a general secrets
store — that boundary with `:openbao` is untouched).

## `:valkey` → resilient multilevel cache

### Components

All new modules live under `lib/new_api_app/valkey/`, namespaced
`NewApiApp.Valkey.*` — the existing `NewApiApp.Valkey` module name becomes the
namespace root rather than the sole module, so everything this plugin
contributes stays discoverable under one prefix.

- **`NewApiApp.Valkey.Cache.L1`** — `use Nebulex.Cache, otp_app: :new_api_app,
  adapter: Nebulex.Adapters.Local`. In-process ETS, the fast path for every
  read.
- **`NewApiApp.Valkey.Cache.L2`** — `use Nebulex.Cache, otp_app: :new_api_app,
  adapter: NebulexRedisAdapter`. Talks to the Valkey sidecar. The adapter
  pools connections internally (`nebulex_redis_adapter`'s own connection-pool
  option), which is what actually closes today's single-named-connection
  bottleneck (`Redix.child_spec/1` currently starts exactly one connection;
  every concurrent caller serializes on it) — no hand-rolled pool needed.
- **`NewApiApp.Valkey.Breaker`** — a lock-free circuit breaker, ported from
  `manage_infra`'s `ManageInfra.Cache.Breaker` (`cache/breaker.ex:33-46,
  169-234`): `:atomics` for the failure counter and state, `:persistent_term`
  for the breaker's config, so a hot-path check never contends a process
  mailbox or an ETS lock. Every `Cache.L2` call runs inside a
  `Task.async/Task.yield` bounded by a configurable `timeout_ms`
  (`breaker.ex:169-191`'s pattern). State machine: closed → open after
  `failure_threshold` consecutive failures; open → half-open after
  `cooldown_ms`; half-open → closed on the next success, or back to open on
  failure.
- **`NewApiApp.Valkey.Cache`** — the public API, replacing today's
  `get/1`/`set/3`: `get/1`, `put/3`, `delete/1`, `put_new/2`, `incr/2`,
  `decr/2`. Reads check `Cache.L1` first; on a miss, a Breaker-guarded
  `Cache.L2` read backfills `L1`. Writes go to `L1` immediately, then through
  the Breaker to `L2`. Matching `manage_infra`'s degrade-safe/propagate split
  (`breaker.ex:55-98` vs. `100-116`): `get`/`put`/`delete` return a safe
  default (`nil`/`:ok`) when the breaker is open — Valkey being down degrades
  the cache to L1-only rather than raising; `put_new`/`incr`/`decr` raise
  instead, because those operations can't fake a result that stays consistent
  once L2 comes back (an `incr` that only touched L1 while L2 was open is a
  lie about the stored value the moment the breaker closes again).
- **`NewApiApp.Valkey.Invalidator`** — subscribes to a topic on the project's
  existing `NewApiApp.PubSub` (already supervised by every `phx.new`-generated
  app regardless of `--no-html --no-assets`; no new pubsub dependency). On
  every `Cache.put/3`/`delete/1`, broadcasts the key so peer nodes evict their
  own `L1` copy — cross-node coherence for a clustered deployment, a no-op
  self-broadcast on a single node. `default_ttl` (below) is the backstop if a
  broadcast is ever lost, exactly as in `manage_infra`
  (`cache/coherent_evict.ex`'s stated rationale, per the earlier research
  pass).

### Dependencies

`{:nebulex, "~> 3.0"}`, `{:nebulex_redis_adapter, "~> 3.0"}` — both verified
live against Hex during spec-writing (not assumed): `nebulex` 3.0.4 and
`nebulex_redis_adapter` 3.0.0 are the current stable releases as of this
writing (Feb 2026), and `nebulex_redis_adapter` itself is Redix-backed
internally. `{:redix, "~> 1.8"}` stays an explicit direct dependency (matching
this project's convention of declaring target-facing deps directly rather
than relying on a transitive resolution) even though `nebulex_redis_adapter`
would pull it in on its own.

Both new deps go at the **front** of `valkey_component/mix.exs`'s `deps()`
list, ahead of the existing `:redix` entry —
`Capstone.Plugin.Apply.add_deps/2` reverses the manifest's `deps:` list before
prepending each one, so a new dep recorded anywhere but the front of the raw
component's own list reproduces a different order on round-trip apply than
the raw component's actual `mix.exs`. This exact defect class was already hit
and fixed twice in this project (commit `a02a106` for `:grpc`, and
`valkey_component/mix.exs` itself the first time it was written) — the
implementation plan must not reintroduce it a third time.

### Config

New keys under `config :new_api_app, NewApiApp.Valkey.Cache`:

```elixir
l1: [gc_interval: :timer.hours(1), max_size: 1_000_000, allocated_memory: 100_000_000],
l2: [pool_size: 5],
breaker: [timeout_ms: 100, failure_threshold: 3, cooldown_ms: :timer.seconds(30)],
default_ttl: :timer.minutes(10)
```

`host`/`port` stay where they are today (`config/dev.exs`, `config/runtime.exs`)
— they configure `Cache.L2`'s connection to the sidecar exactly as they
configure today's `NewApiApp.Valkey`'s.

### `compose.yaml`

Add a named volume for persistence — today's is `docker.io/valkey/valkey:alpine`
with no volume, so a container restart during development loses all data.
`manage_infra`'s own compose (per the earlier research pass) uses
`quay.io/sclorg/valkey-8-c10s` with a named volume; this plugin keeps the
existing `valkey/valkey:alpine` image (no reason found to change images, only
to persist data) and adds:

```yaml
  valkey:
    image: docker.io/valkey/valkey:alpine
    volumes:
      - valkey_data:/data
    ...
volumes:
  valkey_data:
```

The implementation plan must confirm `valkey/valkey:alpine`'s default command
actually persists to `/data` (some Redis-protocol images need an explicit
`--save`/`appendonly` flag to enable persistence rather than persisting by
default) — not assumed here.

### No boot gate on `:valkey`

`manage_infra`'s own boot gate (`ManageInfra.Application.start_after_boot_gate/2`,
`application.ex:157-176`) wraps `Crypto.verify_boot!()`/`Identity.verify_boot!()`
only — it does not gate on Cache/Valkey reachability. This design follows that
precedent deliberately: the entire point of the L1/Breaker design above is to
degrade gracefully when Valkey is unreachable, so blocking application boot on
Valkey's reachability would contradict the resilience this section just built.
A generated project boots fine with Valkey down; reads fall back to
L1-only/degrade-safe defaults per the Breaker's open-state behavior.

## `:openbao` → real auth flow

### Components

New module `lib/new_api_app/vault/auth.ex`, `NewApiApp.Vault.Auth`:

- A supervised `GenServer`, started ahead of everything else in
  `NewApiApp.Application.start/2`'s children list.
- `config[:method]`: `:token` (today's behavior — a static token from config,
  no login round-trip, the zero-setup dev default) or `:approle`
  (`role_id`/`secret_id` posted to `/v1/auth/approle/login`; the response's
  `auth.client_token` and `auth.lease_duration` drive everything below).
  Mirrors `manage_infra`'s `Auth.do_login/0` dispatch (`crypto/auth.ex:86-92`
  for the AppRole branch) minus the `:kubernetes` branch (see "Out of scope").
- **Lease renewal**: schedules a renewal at 2/3 of `lease_duration` via
  `Process.send_after/3` (`auth.ex:19, 135-137`'s pattern). A failed renewal
  re-triggers a full login rather than just erroring (`auth.ex:67-73`).
- **Retry on failed login**: a fixed 5-second backoff via `Process.send_after/3`
  (`auth.ex:18, 47-50`'s pattern) — the GenServer keeps retrying rather than
  crashing (crashing here would just restart into the same failure via the
  supervisor, with no backoff, hammering an unreachable OpenBao).
- Publishes the current token via `:persistent_term` on every successful
  login/renewal, so `NewApiApp.Vault.read_secret/2` reads it without a
  GenServer call per request — the same lock-free hot-path pattern
  `NewApiApp.Valkey.Breaker` uses above, for the same reason (avoids making
  every secret read contend the `Auth` process's mailbox).
- `:token` method still goes through `Auth` (so `current_token/0` has one
  consistent source regardless of method) but skips the login/renewal/retry
  machinery entirely — it publishes the configured static token once at
  `init/1` and does nothing further.

`NewApiApp.Vault.read_secret/2` changes: pulls its token from
`NewApiApp.Vault.Auth.current_token/0` instead of `Keyword.fetch!(config,
:token)`, and sets `receive_timeout` (config-driven) and `retry: false`
explicitly on the `Req.new/1` call — today's call sets neither, so an
unreachable OpenBao can hang a request up to `Req`'s own default timeout.
Gains `NewApiApp.Vault.health/0`: `GET /v1/sys/health`, no auth header needed
(OpenBao's health endpoint doesn't require a token) — an
authentication-independent reachability probe, mirroring
`manage_infra`'s `Transit.health/0` (`transit.ex:57-75`).

### Boot gate

`NewApiApp.Application.start/2` starts `NewApiApp.Vault.Auth` as one of the
first children (ahead of the Endpoint, ahead of anything that might touch
OpenBao). If the initial login fails — `:approle` credentials rejected,
OpenBao unreachable — `Auth`'s `init/1` returns `{:stop, reason}` rather than
retrying in the background for this one specific case: an initial-boot
failure is not the same as a lease expiring mid-run, and OTP's own idiom for
"refuse to start" is a child's `init/1` returning an error, which fails
`start/2`'s `Supervisor.start_link/2` call and therefore `Application.start/2`
itself. This matches `manage_infra`'s fail-closed precedent for OpenBao
specifically (`application.ex:157-176`).

`:token` method's `init/1` never fails this way (there is no login to fail) —
the boot gate has no effect when running with a static token, matching
today's behavior for that case exactly. It only bites once `:approle` is
actually configured.

### `compose.yaml` / dev bootstrap

Dev-mode OpenBao (`BAO_DEV_ROOT_TOKEN_ID` + `-dev`) auto-mounts KV v2 at
`secret/` but does **not** auto-enable the AppRole auth method — a fresh
`podman-compose up -d openbao` today has no AppRole method to log into at
all. `:token` stays the zero-setup default for exactly this reason.
`:approle` needs a one-time bootstrap: enable the AppRole auth method, create
a role with a policy that grants read on `secret/data/*`, and record the
resulting `role_id`/`secret_id`. Add a `mix openbao.setup` task (using the
already-baseline `req` to script the `bao`-equivalent HTTP calls against the
running dev-mode sidecar's root token) that performs this and prints the
`role_id`/`secret_id` for the developer to put in `config/dev.exs` —
mirroring what `manage_infra`'s `deploy/openbao/bootstrap.sh` does via shell
script, but as a mix task since this plugin has no shell-script precedent to
extend and `req`+the dev root token is sufficient to script it in Elixir
directly.

### Config

New keys under `config :new_api_app, NewApiApp.Vault`:

```elixir
method: :token,          # or :approle
token: "new_api_app-dev-root-token",  # :token method, unchanged dev default
role_id: nil,             # :approle method
secret_id: nil,           # :approle method
mount: "approle",
timeout_ms: 5_000
```

`base_url` stays where it is today. `config/runtime.exs`'s existing prod
guard (`OPENBAO_TOKEN` required from env, no default) extends to also accept
`OPENBAO_METHOD`/`OPENBAO_ROLE_ID`/`OPENBAO_SECRET_ID` when `:approle` is
selected in prod — `:token` remains the default method everywhere, `:approle`
is opt-in via config, not a breaking change to what a project boots with out
of the box.

## Testing

- **`NewApiApp.Valkey.Breaker`**: pure unit tests over the atomics/
  persistent_term state machine — closed → open after `failure_threshold`
  consecutive injected failures, open → half-open after `cooldown_ms`
  elapses, half-open → closed on the next success. No live sidecar needed;
  failures are injected by calling the breaker around a function that returns
  `{:error, :boom}` or sleeps past `timeout_ms`.
- **`NewApiApp.Vault.Auth`**: unit tests for login/renewal/retry scheduling,
  stubbing the HTTP layer via `Req.Test` (already this plugin's own pattern —
  `read_secret/2`'s existing moduledoc: "tests use this to inject a `:plug`
  stub instead of hitting a real OpenBao instance"). Covers: successful
  `:approle` login populates `current_token/0`; a login failure retries after
  5s; a lease renewal scheduled at 2/3 `lease_duration` fires and re-logs-in
  on failure.
- **Existing `:valkey`/`:openbao`-tagged tests** (excluded by default,
  `test/new_api_app/valkey_test.exs`/openbao's equivalent) extend to cover,
  against the real dev-mode sidecars: `Cache.get/1`/`put/3` round-tripping
  through `L1`→`L2`; the Breaker actually opening when the Valkey container is
  stopped mid-test and `Cache.get/1` still returning (degrade-safe, not
  hanging); `:approle` login against a bootstrapped dev OpenBao (needs the new
  `mix openbao.setup` task run first — document this as a test prerequisite,
  the same way the toolchain tests already document `pnpm`/`phx_new`
  prerequisites).
- **`test/integration/plugin_lifecycle_test.exs`**'s existing `[:podman,
  :openbao, :valkey]` toolchain test extends to additionally assert: the
  generated project compiles and boots with only `:token` configured (today's
  path, must keep working unchanged); a `:approle`-configured boot against an
  unreachable/misconfigured OpenBao fails `mix run` outright (the boot gate,
  verified for real rather than just unit-tested in isolation).

## Out of scope

- **Kubernetes auth for `:openbao`.** `manage_infra`'s `:kubernetes` method
  reads an in-cluster ServiceAccount JWT
  (`/var/run/secrets/kubernetes.io/serviceaccount/token`) that only exists
  when the process is actually running inside a Kubernetes pod. Capstone's
  own sidecar orchestration is podman/compose, not Kubernetes — there is no
  way to exercise this method in this project's own toolchain, so it would
  ship as dead code. A generated project's own operator can still configure
  `:approle` even when deployed to Kubernetes.
- **TLS, auto-unseal.** Unchanged from the superseded spec's own scope call —
  still orchestrator/operator concerns for wherever the real sidecar runs,
  not something the generated project's client code needs to implement.
- **HA/Sentinel failover for `:valkey`.** `manage_infra`'s
  `ManageInfra.Ops.ValkeyRoleWatcher`/`Sentinel` reconciles a Kubernetes pod
  label against Sentinel's view of the current primary, and is explicitly
  leader-gated (only an elected coordinator acts) — Tier-2/Kubernetes-only
  operational complexity a Tier-0 scaffolded dev sidecar has no use for.
- **OpenBao's Transit and PKI engines.** `manage_infra` additionally uses
  Transit (envelope encryption/rotation) and PKI (certificate issuance) —
  matching `:openbao`'s own already-stated purpose ("Secrets only... general
  KV storage is explicitly `:valkey`'s job"), those are a different, much
  larger feature (envelope encryption / mTLS identity) than this plugin has
  ever claimed to provide, not a gap in its existing scope.
- **A Valkey password / OpenBao TLS on the sidecar connection itself.**
  Unchanged from the superseded spec — still an orchestrator/operator
  concern; the sidecar remains loopback-bound as before.
- **`mix capstone.update` retroactively upgrading an already-generated
  project onto this new module shape.** Confirmed in "Purpose" above:
  `Capstone.Update.run/3` never re-touches an already-recorded plugin,
  regardless of this work. Not a gap this work introduces — there was never
  an upgrade-in-place path for any plugin.

## Verification notes (the implementation plan must re-confirm)

- `{:nebulex, "~> 3.0"}` / `{:nebulex_redis_adapter, "~> 3.0"}` were checked
  live against Hex during spec-writing (3.0.4 / 3.0.0, current stable as of
  this writing) — the implementation plan should re-check at the time it
  actually runs `mix deps.get`, since Hex versions can move between
  spec-writing and implementation.
- `valkey/valkey:alpine`'s default persistence behavior (whether `/data` is
  actually persisted without an explicit `--save`/`appendonly` command
  override) is asserted above, not verified against the image directly —
  confirm before relying on the added volume actually persisting data across
  a container restart.
- Whether OpenBao's dev-mode `-dev` flag's auto-enabled KV v2 mount and
  AppRole bootstrap-ability are exactly as described (an assumption carried
  over from the original `:openbao` design's own dev-mode setup, not
  independently re-verified against a running `openbao/openbao:latest`
  container during spec-writing) — confirm by actually running
  `podman-compose up -d openbao` and exercising the planned `mix
  openbao.setup` bootstrap against it.
- Whether `NebulexRedisAdapter`'s connection-pool option name/shape matches
  what's assumed above (`l2: [pool_size: 5]`), and whether `host`/`port`
  configure the adapter directly or must nest under a `conn_opts:` key —
  confirm against `nebulex_redis_adapter` 3.0.0's actual documented config
  keys, not assumed from an older major version's API or from
  `Redix.child_spec/1`'s own (different) shape.
