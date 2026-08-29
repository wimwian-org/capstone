# `:openbao` plugin — secrets vault sidecar — design

## Purpose

Give a generated project an optional OpenBao (Vault-compatible) secrets
sidecar: a `compose.yaml` service for local/test use under podman or docker
compose, an `<%= @module %>.Vault` module that reads secrets from its KV v2
HTTP API, and environment-gated config wiring so production points at a real,
separately operated OpenBao deployment instead.

This mirrors `docs/guides/building-a-plugin.md`'s own canonical example
almost exactly — a `:valkey`-style sidecar plugin — with one deliberate
divergence from that example, explained under "Known limitation" below.

## The test/production split

The request this plugin answers is explicit about two different
environments, and the design keeps them structurally separate rather than
parameterising one compose file for both:

- **Test, deployed in podman.** `compose.yaml`'s `openbao` service runs
  OpenBao in `-dev` mode with a fixed root token
  (`<%= @app %>-dev-root-token`), unsealed and ready the instant the
  container starts. `podman-compose up` or `docker compose up` both work —
  the file uses only Compose Specification keys (`image`, `environment`,
  `cap_add`, `ports`, `healthcheck`), nothing docker-proprietary, and
  `compose.yaml` (not `podman-compose.yml`) is the Compose Specification's own
  filename, recognised by both tools without a `-f` flag.
- **Production, an OCI-compliant container.** Production never runs this
  compose file at all. `config/runtime.exs`'s `if config_env() == :prod do`
  branch requires `OPENBAO_ADDR` and `OPENBAO_TOKEN` from the environment,
  raising loudly if either is missing, and points at wherever OpenBao is
  actually operated — a real cluster, not a sidecar. The app's own production
  image (this repo's `:prod_image_api` plugin, or any other OCI-compliant
  build) needs nothing OpenBao-specific baked in beyond those two env vars.

## Image choice

`docker.io/openbao/openbao:latest` — OpenBao publishes to three registries
(`docker.io`, `quay.io`, `ghcr.io`) in two variants each: a default
Alpine-based image and a `-ubi` (RHEL UBI) one. `docker.io/openbao/openbao`
is the Alpine variant, matching the fully-qualified-registry convention
`priv/meta/meta_openapi/files/compose.yaml.eex` already set with
`docker.io/library/postgres:17-alpine`. `:latest` rather than a pinned
version: this is a dev-mode convenience sidecar, not a production
dependency pin.

Verified empirically (Task 1 below): `podman-compose up` against this exact
service definition produces a healthy, unsealed OpenBao 2.6.1 server within
one healthcheck interval, and a KV v2 write/read round-trip against it
succeeds with the fixed dev token.

## `<%= @module %>.Vault`

```elixir
def read_secret(path, opts \\ []) do
  config = Application.fetch_env!(:<%= @app %>, __MODULE__)
  base_url = Keyword.fetch!(config, :base_url)
  token = Keyword.fetch!(config, :token)

  req_opts = Keyword.merge([base_url: base_url, headers: [{"x-vault-token", token}]], opts)
  request = Req.new(req_opts)

  case Req.get(request, url: "/v1/secret/data/#{path}") do
    {:ok, %Req.Response{status: 200, body: %{"data" => %{"data" => data}}}} -> {:ok, data}
    {:ok, %Req.Response{status: 404}} -> {:error, :not_found}
    {:ok, %Req.Response{status: status}} -> {:error, {:unexpected_status, status}}
    {:error, reason} -> {:error, reason}
  end
end
```

No dedicated Vault/Bao client library is needed: OpenBao's KV v2 engine is a
plain HTTP API, and `req` is already a baseline dependency of every
generated project (`priv/meta/baseline_api/mix.exs`). `manifest.exs` records
`deps: []` for this plugin — confirmed by `mix capstone.plugin.derive`
finding no `mix.exs` diff to extract.

`opts` merges into the `Req.new/1` call precisely so tests can inject a
`:plug` stub (`Req.Test`) instead of a real OpenBao instance — the pattern
`test/<%= @app %>/vault_test.exs` uses.

## Config wiring

- `config/dev.exs`, `config/test.exs` — both append (`:contributes`, default
  `at: :append`) a `config :<%= @app %>, <%= @module %>.Vault, base_url:
  ..., token: ...` block defaulting to the same fixed dev-mode token
  `compose.yaml` seeds the sidecar with, so nothing extra needs setting up
  locally, in test, or in dev.
- `config/runtime.exs` — contributes (`:contributes`, `at: {:env, :prod}`)
  inside the existing `if config_env() == :prod do ... end` guard, raising if
  `OPENBAO_TOKEN` is absent, exactly alongside `database_url` and
  `secret_key_base`'s existing pattern in that same file. This is
  `Capstone.Source.ConfigExs.insert_in_env/3` — proven in
  `test/capstone/source/config_exs_test.exs` against this exact baseline
  file before this plugin existed — used here for the first time by any
  first-party plugin.

Placement inside that guard is not incidental: appending an OpenBao token
requirement unguarded would make it a hard requirement in dev and test too,
where the whole point is that nothing beyond the compose sidecar is needed.

## Known limitation: `compose.yaml` ownership

`priv/meta/meta_openapi/manifest.exs` already claims `compose.yaml` as
`:sole_owner` (for its own Postgres + app service definitions), and this
plugin does the same. `:sole_owner` writes unconditionally
(`Capstone.Plugin.Apply.write_owned/4`) — the LAST plugin applied wins the
whole file. `:openapi` and `:openbao` therefore cannot both be applied to one
project today without one silently discarding the other's `compose.yaml`.

The doc example this plugin otherwise mirrors uses `:contributes` with a
`key:` for exactly this reason — but `:contributes` requires the file to
already exist (`Capstone.Plugin.Apply.contribute/5` calls `File.read!/1`
unconditionally), and nothing yet provides a `:seed`-mode base `compose.yaml`
scaffold for sidecars to append into. `:seed` is declared in
`Capstone.Plugin.Behavior`'s mode enum and validated in
`Capstone.Manifest`, but `Capstone.Plugin.Apply.entry/4` has no clause for
it — it is not reachable from any plugin today.

Resolving this (a `:seed`-mode compose scaffold, `:openapi` and future
`:valkey`/`:nginx` sidecars all contributing into it) is out of scope here
and left as follow-up work; this plugin ships consistent with the one
existing precedent (`:openapi`) rather than inventing a new core `Apply`
primitive to solve a problem no shipped plugin has yet needed solved.

## Testing

`test/<%= @app %>/vault_test.exs` stubs the HTTP transport with `Req.Test`
and runs unconditionally — no live OpenBao needed, so `mix test` passes out
of the box in every generated project, exactly like every other plugin's
committed test.

**Deliberately deferred**: a `test/<%= @app %>/vault_real_test.exs` against
the real compose sidecar, tagged `:openbao` and excluded by default (the
`options/07-openbao.md` design this plugin is adapted from calls for
exactly this). Excluding a tag by default requires rewriting
`ExUnit.start()` to `ExUnit.start(exclude: [:openbao])` in the generated
project's `test/test_helper.exs` — a structural edit to an *existing call's
arguments*, which none of `:sole_owner`, `:contributes`, or `:manual` can
express (`:manual` only inserts after an anchor; it cannot rewrite one).
Every other shipped plugin leaves `test/test_helper.exs` untouched
(`priv/baselines.exs` records an identical hash for it across every entry).
Adding this would mean a new `Capstone.Source.TestHelperExs` structural-edit
module (mirroring `ConfigExs`/`ApplicationEx`/`MixExs`) plus a new `Apply`
dispatch — real work, but a separate change from this one.

## Composability

Compatible with `:cache`, `:cqrs`, and `:grpc` — none of them touch
`compose.yaml`, `config/dev.exs`, `config/test.exs`, `config/runtime.exs`,
or any `lib/<%= @app %>/vault.ex`-shaped path. Not compatible with
`:openapi` applied to the same project (see "Known limitation" above); no
test asserts that combination, and none should until the compose-ownership
model changes.

## Out of scope

- A `:podman`/`:container_runtime`-providing plugin, and the
  `requires`/`provides`/`conflicts` capability graph
  `Capstone.Plugin.Behavior` declares for hand-authored plugins. Neither is
  consumed by anything today (`Capstone.Plugin.Apply` applies whatever
  `plugins:` a target lists, in list order, with no resolver reading those
  three callbacks at all), and the first-party derived-plugin manifest
  format (`deps`/`files`/`name`/`version`/`aliases`/`project`) that this
  plugin uses has no equivalent fields regardless.
- Wiring `target.exs`'s existing `container: [sidecars: [openbao: true]]`
  shape (`Capstone.Config.Container.Sidecars`, present since the initial
  commit) to actually select this plugin. That shape is validated but inert
  today — nothing reads it to decide which plugins to apply — and connecting
  it is `target.exs`'s `schema_version: 2` work, not this plugin's.
- AppRole/Kubernetes auth, TLS between the app and OpenBao, or auto-unseal.
  All are real production OpenBao concerns, and all are the operator's
  responsibility for whatever real OpenBao deployment `OPENBAO_ADDR` points
  at — orthogonal to what a generated project's own code needs to talk to
  it.

## Verification notes (empirical checks the implementation re-confirmed)

- `podman-compose -f compose.yaml up -d` against this exact file: container
  reports `healthy` on the first healthcheck attempt; logs show `core: vault
  is unsealed` and the configured root token immediately after start.
- `curl -X POST .../v1/secret/data/<%= @app %>/db` then a matching `GET`,
  both authenticated with the fixed dev token, round-trip the written JSON
  through the exact `data.data` nesting `<%= @module %>.Vault.read_secret/2`
  pattern-matches on.
- `mix capstone.plugin.derive openbao` classified every modified config file
  automatically — `config/dev.exs` and `config/test.exs` as `:contributes`
  with no `at:` (plain append), `config/runtime.exs` as `:contributes` with
  `at: {:env, :prod}` — with no `:manual` fallback anywhere in the manifest.
- The round-trip test (`test/capstone/plugin/openbao_round_trip_test.exs`)
  confirms applying `meta_openbao` to a fresh `baseline_api` copy reproduces
  `openbao_component` byte-for-byte, is idempotent on a second apply, and
  renames correctly into a differently-named project.
- The toolchain test (`test/integration/plugin_lifecycle_test.exs`) confirms
  a real `mix capstone.new` with `plugins: [:openbao]` compiles and passes
  `mix test` without ever starting the compose sidecar.
