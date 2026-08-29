# OpenBao Plugin Implementation Plan

> **Superseded.** The design this plan implements
> (`docs/superpowers/specs/2026-08-29-openbao-plugin-design.md`) is itself
> superseded by
> `docs/superpowers/specs/2026-08-29-container-sidecars-design.md` —
> `compose.yaml` is `:contributes` against an `:api_podman` baseline now, not
> `:sole_owner` against bare `:api` as every task below assumes. Kept as the
> historical record of the first draft's task breakdown.

See `docs/superpowers/specs/2026-08-29-openbao-plugin-design.md` for the
design this implements.

## Global Constraints

- Built via the existing pipeline: hand-edit `priv/meta/openbao_component/`
  (a real, compiling copy of `priv/meta/baseline_api/`), then
  `mix capstone.plugin.derive openbao` diffs it against `baseline_api` into
  `priv/meta/meta_openbao/manifest.exs`. Never hand-edit files under
  `priv/meta/meta_openbao/` directly — they are `derive`'s generated output.
- `req` is already a `baseline_api` dependency (`~> 0.5`) — no new dep.
- `config/runtime.exs`'s added block must land exactly where
  `Capstone.Source.ConfigExs.insert_in_env/3`'s `splice_inside/3` would place
  it (immediately after the `if config_env() == :prod do` guard's *last
  expression*, not at the end of the guard) — otherwise `derive` cannot
  reproduce it via replay and falls back to a `:manual` conflict region.
- `compose.yaml` is claimed `:sole_owner`, matching `:openapi`'s existing
  precedent — see the design doc's "Known limitation" section for why this
  (not `:contributes`) is the correct choice today.
- Real-sidecar integration testing (`vault_real_test.exs` + a
  `test/test_helper.exs` exclude-tag edit) is explicitly deferred — see the
  design doc's "Testing" section.

## File Structure

```
priv/meta/openbao_component/          # raw, compiling project (new)
  compose.yaml                        # new
  lib/new_api_app/vault.ex            # new
  test/new_api_app/vault_test.exs     # new
  README.md                           # modified (append)
  config/dev.exs                      # modified (append)
  config/test.exs                     # modified (append)
  config/runtime.exs                  # modified (insert inside prod guard)
priv/meta/meta_openbao/               # derived output (generated, not hand-edited)
priv/baselines.exs                    # new `openbao:` entry
test/capstone/plugin/openbao_round_trip_test.exs   # new
test/integration/plugin_lifecycle_test.exs         # new @tag :toolchain test
```

### Task 1: Scaffold `priv/meta/openbao_component/` and verify the sidecar for real

- Produces: a compiling raw project with `compose.yaml`, `NewApiApp.Vault`,
  config wiring in `dev.exs`/`test.exs`/`runtime.exs`, a README section, and
  a passing mocked test.
- Consumes: `priv/meta/baseline_api/` (copied wholesale as the starting
  point).

```bash
cp -R priv/meta/baseline_api priv/meta/openbao_component
```

Add `compose.yaml`:

```yaml
services:
  # Sidecar -- optional secrets vault, not required for the app to boot or for
  # tests to pass. Runs in dev mode with a fixed root token so
  # `mix test --include openbao` can authenticate deterministically. Dev mode
  # only -- never use a fixed root token outside local development/testing.
  #
  # Production does not run this service at all: config/runtime.exs's prod
  # branch reads OPENBAO_ADDR/OPENBAO_TOKEN from the environment, pointing at
  # a separately operated OpenBao deployment instead.
  openbao:
    image: docker.io/openbao/openbao:latest
    environment:
      BAO_DEV_ROOT_TOKEN_ID: new_api_app-dev-root-token
      BAO_DEV_LISTEN_ADDRESS: 0.0.0.0:8200
    cap_add:
      - IPC_LOCK
    ports:
      - "8200:8200"
    healthcheck:
      test: ["CMD", "bao", "status", "-address=http://127.0.0.1:8200"]
      interval: 2s
      timeout: 3s
      retries: 15
```

Add `lib/new_api_app/vault.ex` (see the design doc for the full module).

Append to `config/dev.exs` and `config/test.exs` (identical block, different
comment):

```elixir
config :new_api_app, NewApiApp.Vault,
  base_url: System.get_env("OPENBAO_ADDR", "http://localhost:8200"),
  token: System.get_env("OPENBAO_TOKEN", "new_api_app-dev-root-token")
```

Insert into `config/runtime.exs`, immediately after
`config :new_api_app, NewApiAppWeb.Endpoint, ... secret_key_base:
secret_key_base` and before the `# ## SSL Support` comment (this exact
position matters — see Global Constraints):

```elixir
  openbao_token =
    System.get_env("OPENBAO_TOKEN") ||
      raise """
      environment variable OPENBAO_TOKEN is missing.
      """

  config :new_api_app, NewApiApp.Vault,
    base_url: System.get_env("OPENBAO_ADDR", "http://localhost:8200"),
    token: openbao_token
```

Append a `## OpenBao` section to `README.md`.

Add `test/new_api_app/vault_test.exs`, stubbing `Req.Test` for the 200/404/500
cases (see the design doc).

Verify:

```bash
cd priv/meta/openbao_component
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test
cd -
```

Then verify the compose file for real, against an actual podman machine —
this is the empirical check the design doc's "Verification notes" section
records:

```bash
cd priv/meta/openbao_component
podman-compose -f compose.yaml up -d
# wait for `podman inspect --format '{{.State.Health.Status}}' openbao_component_openbao_1` == healthy
curl -s http://localhost:8200/v1/sys/health
curl -s -X POST -H "X-Vault-Token: new_api_app-dev-root-token" \
  -d '{"data":{"username":"demo"}}' http://localhost:8200/v1/secret/data/new_api_app/db
curl -s -H "X-Vault-Token: new_api_app-dev-root-token" \
  http://localhost:8200/v1/secret/data/new_api_app/db
podman-compose -f compose.yaml down
cd -
```

```bash
git add priv/meta/openbao_component
git commit -m "feat(plugin): add openbao_component, an OpenBao secrets vault sidecar"
```

### Task 2: Derive the `:openbao` manifest and record real baseline hashes

- Produces: `priv/meta/meta_openbao/manifest.exs`, consumed by Task 3's
  round-trip test and Task 4's toolchain test.
- Consumes: `priv/meta/openbao_component/` (Task 1).

Add a minimal entry to `priv/baselines.exs` (alphabetically between
`openapi:` and `prod_image_api:`):

```elixir
openbao: %{
  derived_from: :api,
  names: %{app: "new_api_app", module: "NewApiApp", name: "new_api_app"},
  path: "priv/meta/openbao_component"
},
```

```bash
mix capstone.plugin.derive openbao
```

**Inspect `priv/meta/meta_openbao/manifest.exs` before continuing.** Every
config file must show `:contributes` — `config/runtime.exs` specifically
must show `at: {:env, :prod}`. If ANY file fell back to `:manual`, STOP:
re-check Task 1's exact insertion point rather than shipping a conflict-marker
plugin.

```bash
mix capstone.baseline.record
```

The `openbao` entry now needs a hand-authored `normalisations:` field — the
`record` task only recomputes `files`/`tree_digest`, and every other
`:api`-derived baseline's four secret-bearing files apply here identically
(`openbao_component` is a copy of `baseline_api`, which already carries the
same placeholder secrets):

```elixir
normalisations: [
  {:secret, "config/config.exs", :signing_salt},
  {:secret, "config/dev.exs", :secret_key_base},
  {:secret, "config/test.exs", :secret_key_base},
  {:secret, "lib/new_api_app_web/endpoint.ex", :signing_salt}
],
```

Run `mix test test/capstone/baseline_test.exs` to confirm — its "exactly the
recorded files are normalised, and no others" test catches a missing entry
immediately.

```bash
git status --porcelain *.tar.gz   # confirm the root snapshot archives are untracked
rm -f *.tar.gz                    # regenerable; don't let them clutter the tree
git add priv/meta/meta_openbao priv/baselines.exs
git commit -m "feat(plugin): derive the :openbao manifest, record real baseline hashes"
```

### Task 3: Round-trip test for `:openbao`

- Produces: `test/capstone/plugin/openbao_round_trip_test.exs`.
- Consumes: `priv/meta/meta_openbao/manifest.exs`, `priv/meta/openbao_component/`
  (Task 2).

Mirrors `test/capstone/plugin/grpc_round_trip_test.exs` exactly: applying
`meta_openbao` to a fresh `baseline_api` copy reproduces `openbao_component`
byte-for-byte, a second apply is a no-op, and applying into a differently-named
project renames every reference correctly.

```bash
mix test test/capstone/plugin/openbao_round_trip_test.exs
```

```bash
git add test/capstone/plugin/openbao_round_trip_test.exs
git commit -m "test(plugin): add a round-trip test for the :openbao plugin"
```

### Task 4: `:openbao` structural toolchain test

- Produces: a `@tag :toolchain` test in `test/integration/plugin_lifecycle_test.exs`.
- Consumes: `priv/baselines.exs`'s `:openbao` entry, `priv/meta/meta_openbao/manifest.exs`
  (Task 2).

Generates a real project with `plugins: [:openbao]` via `mix capstone.new`,
asserts `compose.yaml` and `lib/<app>/vault.ex` exist and the config
contributions landed without leaving a conflict marker, then `mix compile`
and `mix test` the generated project — no live sidecar involved, since
`vault_test.exs` stubs the HTTP transport. Needs `@tag timeout:
:timer.minutes(3)`, matching `:grpc`'s and `:cqrs`'s equivalent tests — the
default 60s is too tight for a fresh project's `deps.get`/`deps.compile`/`test`.

Needs the plugin packaged and locally installed first (this branch's
established workaround — no published release carries `:openbao` yet):

```bash
mix capstone.plugin.package openbao
cp priv/plugins/openbao-*.tar.gz ~/Library/Caches/capstone/plugins/
mix test test/integration/plugin_lifecycle_test.exs --include toolchain
```

```bash
git add test/integration/plugin_lifecycle_test.exs
git commit -m "test(plugin): add a structural toolchain test for the :openbao plugin"
```

### Task 5: Full gate

```bash
mix format --check-formatted
mix credo --strict
mix dialyzer
mix doctor
mix sobelow
mix coveralls
mix test --include toolchain
```

If clean, nothing further to commit.
