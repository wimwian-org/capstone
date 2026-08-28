# CQRS Plugin — Event-Sourced Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the `:cqrs` plugin as a real event-sourced system on `commanded` + `eventstore` — aggregates persisted as event streams, commands dispatched through Commanded, and a two-layer uniqueness mechanism (Nebulex fast pre-check + a deterministic-identity "Reservation" aggregate as race-proof ground truth) replacing the old direct-Ecto-insert design.

**Architecture:** `NewApiApp.EventStore` (real, Postgres-backed) + `NewApiApp.CQRS.App` (a `Commanded.Application`) are the backbone; `NewApiApp.CQRS.Reservation` is a fully generic, capstone-shipped aggregate whose atomic per-stream creation is the uniqueness ground truth; `NewApiApp.CQRS.Dispatcher` is the single entry point, returning `:ok | {:error, reason}` (not the created struct — projections are async). No domain aggregate, command, event, Router, or projection ships in the plugin tree; the README carries a complete worked example instead.

**Tech Stack:** Elixir 1.20, Phoenix 1.8, Commanded 1.4, EventStore 1.4 (`commanded_eventstore_adapter`), Nebulex 3.0 (`Nebulex.Adapters.Local` + `Nebulex.Adapters.Local`'s separate `nebulex_local` package), Uniq 0.6 (`Uniq.UUID`, v7 for entity identity, v5 for deterministic reservation identity).

**Spec:** `docs/superpowers/specs/2026-08-28-cqrs-eventsourcing-design.md` (supersedes the `:cqrs` half of `docs/superpowers/specs/2026-08-27-cqrs-plugin-design.md`; that spec's `:cache` half is already implemented and is NOT touched by this plan).

## Global Constraints

- The plugin is built via the existing pipeline: hand-edit `priv/meta/cqrs_component/`, then `mix capstone.plugin.derive cqrs` diffs it against `priv/meta/baseline_api/` into `priv/meta/meta_cqrs/manifest.exs`. Never hand-edit files under `priv/meta/meta_cqrs/` directly.
- `priv/meta/cqrs_component/mix.exs` already has `{:nebulex, "~> 3.0"}`, `{:nebulex_local, "~> 3.0"}`, `{:uniq, "~> 0.6"}` from prior, already-committed work (`git log --oneline -- priv/meta/cqrs_component/mix.exs`) — do not re-add them. This plan's own deps additions are only `{:commanded, "~> 1.4"}`, `{:commanded_eventstore_adapter, "~> 1.4"}`, `{:eventstore, "~> 1.4"}`.
- `priv/meta/cqrs_component/lib/new_api_app/cqrs/cache.ex` already exists on disk (uncommitted, from an abandoned prior attempt at a different `:cqrs` design) and matches this plan's Task 3 verbatim — reuse it as-is, do not rewrite it. `priv/meta/cqrs_component/lib/new_api_app/cqrs/unique_check.ex` and `priv/meta/cqrs_component/test/cqrs/unique_check_test.exs` ALSO already exist uncommitted but implement the OLD, superseded Ecto.Changeset-based design — Task 4 overwrites both completely; do not preserve any of their current content.
- `application.ex`'s existing auto-detection (`Derive.added_child/2`) only captures a supervision-child edit as `:contributes` when exactly ONE child is appended. This plugin appends THREE (`NewApiApp.EventStore`, `NewApiApp.CQRS.App`, `NewApiApp.CQRS.Cache`) in Task 6 — **this is expected to fall back to a `:manual` anchor**, unlike `:cache`'s single-child `:contributes` capture. Do not try to force auto-detection; verify the `:manual` classification in Task 7 and build every later task (round-trip test, structural toolchain test) around it.
- A `config/config.exs` edit is auto-detected as `:before_import` when the new `config :app, ...` block(s) are inserted immediately before the trailing `import_config "#{config_env()}.exs"` line, with nothing else in the file touched. Multiple tasks (1, 2) each extend this SAME contiguous block — by the time Task 7 runs `derive`, the combined block (EventStore config + CQRS.App config) must still be one uninterrupted insertion right before `import_config`, nothing else in the file touched by any task.
- `config/test.exs` needs a NEW kind of edit (an InMemory-adapter override for `NewApiApp.CQRS.App`) that no existing plugin has ever made — this file has no trailing `import_config` line, so the `:before_import` mechanism does not apply. Task 2 appends the override at the file's end; Task 7 empirically confirms how `derive` classifies it (most likely `:manual`, since `Capstone.Plugin.Apply`'s manual-anchor mechanism is file-agnostic) and documents the actual outcome — do not assume `:contributes`.
- `Commanded.Serialization.JsonSerializer` (not `EventStore.JsonSerializer`) is required in `NewApiApp.EventStore`'s config for Commanded integration — verified against `eventstore`'s own hexdocs.
- Real EventStore mix tasks (verified against `commanded/eventstore`'s own task modules): `mix event_store.create` (provisions the database), `mix event_store.init` (creates the event store's schema/tables). `mix event_store.migrate` is only for upgrading an *existing* store's schema later — not needed on first setup.
- Two UUID conventions, never interchanged: `Uniq.UUID.uuid7/1` (random, time-ordered) for a developer's own entity aggregate identity (README convention only — capstone ships no entity); `Uniq.UUID.uuid5/3` (deterministic, name-based) internally inside `NewApiApp.CQRS.UniqueCheck` for `NewApiApp.CQRS.Reservation`'s stream ids.
- `NewApiApp.CQRS.Reservation`'s `execute/2`/`apply/2` shape (a `released: true` initial/post-release state, `Reserve`/`Release` commands, `Reserved`/`Released` events) is exact — implement precisely as the spec and this plan give it, not a simplified variant.
- `NewApiApp.CQRS.Dispatcher.dispatch/2` returns `:ok | {:error, reason}` — **never** `{:ok, struct}`. Fetching the projected read-model row is a separate `Dispatcher.query/2` call after `:ok`.
- No fixture Ecto schema, migration, domain aggregate, event, command, Router, or event handler is ever added to `priv/meta/cqrs_component/` — capstone doesn't know a consuming project's domain. The one task that needs all of these (Task 10, the real-EventStore integration test) writes them directly into a freshly bootstrapped temp project under capstone's own `test/integration/`, never into `cqrs_component`.
- A local Postgres is running (`postgres`/`postgres`, `localhost`) for the app's normal `Repo` database AND is now also used for a distinct EventStore database (`new_api_app_eventstore_<env>`, a separate database, not a separate schema in the same one) — confirm with `pg_isready` before Task 10.
- Any `--include toolchain` test that applies `:cache` and/or `:cqrs` via `Bootstrap.run/2` pulls from the real, network-published GitHub release registry, not this working tree's `priv/meta/`. `:cqrs` has never been published; `:cache`'s published release still ships its pre-fix stub. Every task here that runs such a test (Tasks 9, 10) needs the sanctioned local-packaging workaround already used earlier on this branch: `mix capstone.plugin.package <name>` (writes a gitignored archive under `priv/plugins/`), then copy that file into `~/Library/Caches/capstone/plugins/` (the directory `Capstone.Plugin.Registry.default_dir/0` reads from — `Registry.resolve!/4` picks the highest-version archive present, no network call, nothing committed/pushed).
- Several Commanded/EventStore runtime specifics were verified against hexdocs summaries, not exact source, and must be re-confirmed empirically the first time each is exercised (adjust the code if reality differs, the way `nebulex_local` was discovered and folded in during this branch's earlier `:cache` work): `Commanded.EventStore.Adapters.InMemory.reset!/1`'s exact arity/argument; whether `Commanded.Commands.Router`'s `dispatch/2` macro accepts a list of command modules sharing one `to:`/`identity:` clause (fall back to two separate `dispatch` calls if not); whether `start_supervised!/1` works directly on a `Commanded.Application` module the same way it does on a GenServer.

---

## File Structure

**`:cqrs` plugin** (all under `priv/meta/cqrs_component/`, hand-edited; `priv/meta/meta_cqrs/` regenerated by `derive`):
- Modify `mix.exs` — add the three new deps.
- Create `lib/new_api_app/event_store.ex`.
- Create `lib/new_api_app/cqrs/app.ex`.
- Create `lib/new_api_app/cqrs/reservation.ex`, `reservation/commands.ex`, `reservation/events.ex`, `reservation/router.ex`.
- Confirm/commit `lib/new_api_app/cqrs/cache.ex` (already drafted).
- Rewrite `lib/new_api_app/cqrs/unique_check.ex` (already drafted with the old, superseded API).
- Create `lib/new_api_app/cqrs/command.ex`, `query.ex`, `dispatcher.ex`.
- Create `test/cqrs/reservation_test.exs`, `unique_check_test.exs` (rewrite), `dispatcher_test.exs`.
- Modify `lib/new_api_app/application.ex` — append three supervision children.
- Modify `config/config.exs` — EventStore + CQRS.App config blocks before `import_config`.
- Modify `config/test.exs` — InMemory adapter override.
- Modify `README.md` — full worked example + `mix event_store.create/init` setup steps.

**Capstone's own repo:**
- Modify `priv/baselines.exs` — recomputed by `mix capstone.baseline.record` (Task 7); the `:cqrs` entry itself already exists from prior work, unchanged in shape.
- Create `test/capstone/plugin/cqrs_round_trip_test.exs`.
- Modify `test/integration/plugin_lifecycle_test.exs` — new `:cqrs` and `:cache`+`:cqrs` structural tests.
- Create `test/integration/cqrs_dispatch_test.exs` — the real-EventStore/Postgres integration test.

---

### Task 1: `NewApiApp.EventStore` and its deps

**Files:**
- Modify: `priv/meta/cqrs_component/mix.exs`
- Create: `priv/meta/cqrs_component/lib/new_api_app/event_store.ex`
- Modify: `priv/meta/cqrs_component/config/config.exs`

**Interfaces:**
- Produces: `NewApiApp.EventStore`, a real `EventStore` module — consumed by Task 2's `NewApiApp.CQRS.App` config.

- [ ] **Step 1: Add the three new deps to `mix.exs`**

Find the existing `deps/0` list (ends with `{:nebulex, "~> 3.0"}, {:nebulex_local, "~> 3.0"}, {:uniq, "~> 0.6"}`). Append, in this order:

```elixir
      {:nebulex, "~> 3.0"},
      {:nebulex_local, "~> 3.0"},
      {:uniq, "~> 0.6"},
      {:commanded, "~> 1.4"},
      {:commanded_eventstore_adapter, "~> 1.4"},
      {:eventstore, "~> 1.4"}
```

- [ ] **Step 2: Create `lib/new_api_app/event_store.ex`**

```elixir
defmodule NewApiApp.EventStore do
  use EventStore, otp_app: :new_api_app
end
```

- [ ] **Step 3: Add the config block to `config/config.exs`**

Insert immediately before the trailing `import_config` line, nothing else in the file changed:

```elixir
# Configure the CQRS event store
config :new_api_app, NewApiApp.EventStore,
  serializer: Commanded.Serialization.JsonSerializer,
  username: "postgres",
  password: "postgres",
  database: "new_api_app_eventstore_#{config_env()}",
  hostname: "localhost"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
```

- [ ] **Step 4: Verify it compiles**

```bash
cd priv/meta/cqrs_component
mix deps.get
mix compile --warnings-as-errors
cd -
```

Expected: compiles cleanly. `NewApiApp.EventStore` isn't started by anything yet (no supervision wiring until Task 6), so this step only proves the module and config are syntactically and structurally valid — not that a real event store connection works. If `mix deps.get` fails to resolve `commanded`/`commanded_eventstore_adapter`/`eventstore`, treat it as a real problem to diagnose (version conflict, hex availability), not something to route around.

- [ ] **Step 5: Commit**

```bash
git add priv/meta/cqrs_component/mix.exs \
        priv/meta/cqrs_component/lib/new_api_app/event_store.ex \
        priv/meta/cqrs_component/config/config.exs \
        priv/meta/cqrs_component/mix.lock
git commit -m "feat(plugin): add commanded/eventstore deps and NewApiApp.EventStore"
```

---

### Task 2: `NewApiApp.CQRS.Reservation` and `NewApiApp.CQRS.App`

**Files:**
- Create: `priv/meta/cqrs_component/lib/new_api_app/cqrs/reservation.ex`
- Create: `priv/meta/cqrs_component/lib/new_api_app/cqrs/reservation/commands.ex`
- Create: `priv/meta/cqrs_component/lib/new_api_app/cqrs/reservation/events.ex`
- Create: `priv/meta/cqrs_component/lib/new_api_app/cqrs/reservation/router.ex`
- Create: `priv/meta/cqrs_component/lib/new_api_app/cqrs/app.ex`
- Create: `priv/meta/cqrs_component/test/cqrs/reservation_test.exs`
- Modify: `priv/meta/cqrs_component/config/config.exs`
- Modify: `priv/meta/cqrs_component/config/test.exs`

**Interfaces:**
- Consumes: `NewApiApp.EventStore` (Task 1, referenced only in dev/prod config, not by the InMemory-backed test in this task).
- Produces: `NewApiApp.CQRS.Reservation`, `.Reservation.Commands.{Reserve,Release}`, `.Reservation.Events.{Reserved,Released}`, `.Reservation.Router`, `NewApiApp.CQRS.App` — all consumed by Task 4's `UniqueCheck` and Task 5's `Dispatcher`.

- [ ] **Step 1: Create `lib/new_api_app/cqrs/reservation/commands.ex`**

```elixir
defmodule NewApiApp.CQRS.Reservation.Commands.Reserve do
  @enforce_keys [:reservation_id]
  defstruct [:reservation_id]
end

defmodule NewApiApp.CQRS.Reservation.Commands.Release do
  @enforce_keys [:reservation_id]
  defstruct [:reservation_id]
end
```

- [ ] **Step 2: Create `lib/new_api_app/cqrs/reservation/events.ex`**

```elixir
defmodule NewApiApp.CQRS.Reservation.Events.Reserved do
  @enforce_keys [:reservation_id]
  defstruct [:reservation_id]
end

defmodule NewApiApp.CQRS.Reservation.Events.Released do
  @enforce_keys [:reservation_id]
  defstruct [:reservation_id]
end
```

- [ ] **Step 3: Create `lib/new_api_app/cqrs/reservation.ex`**

```elixir
defmodule NewApiApp.CQRS.Reservation do
  @moduledoc """
  A minimal aggregate whose entire purpose is uniqueness ground truth.
  Its identity IS the reservation: a deterministic stream id derived from
  a schema tag, a field group, and that group's values
  (see NewApiApp.CQRS.UniqueCheck.reservation_id/3). Dispatching Reserve
  to an id that already has an active Reserved applied fails — this is
  race-proof because the event store serializes appends per stream.

  Event streams are append-only — a reservation can never be deleted, so
  a failed/aborted create (a later unique-field group taken, or the real
  domain command's own dispatch failing afterward) must explicitly
  dispatch Release to free the id for reuse; a successful create simply
  never releases it, leaving the reservation permanent (correct — the
  value is now genuinely, permanently taken by the real entity).
  """

  defstruct [:id, released: true]

  alias NewApiApp.CQRS.Reservation.Commands.Release
  alias NewApiApp.CQRS.Reservation.Commands.Reserve
  alias NewApiApp.CQRS.Reservation.Events.Released
  alias NewApiApp.CQRS.Reservation.Events.Reserved

  def execute(%__MODULE__{released: true}, %Reserve{reservation_id: id}) do
    %Reserved{reservation_id: id}
  end

  def execute(%__MODULE__{released: false}, %Reserve{}) do
    {:error, :already_reserved}
  end

  def execute(%__MODULE__{released: false}, %Release{reservation_id: id}) do
    %Released{reservation_id: id}
  end

  def execute(%__MODULE__{released: true}, %Release{}) do
    {:error, :not_reserved}
  end

  def apply(%__MODULE__{} = state, %Reserved{reservation_id: id}) do
    %__MODULE__{state | id: id, released: false}
  end

  def apply(%__MODULE__{} = state, %Released{}) do
    %__MODULE__{state | released: true}
  end
end
```

- [ ] **Step 4: Create `lib/new_api_app/cqrs/reservation/router.ex`**

```elixir
defmodule NewApiApp.CQRS.Reservation.Router do
  use Commanded.Commands.Router

  dispatch([
    NewApiApp.CQRS.Reservation.Commands.Reserve,
    NewApiApp.CQRS.Reservation.Commands.Release
  ],
    to: NewApiApp.CQRS.Reservation,
    identity: :reservation_id
  )
end
```

If `mix compile` rejects the list-form `dispatch/2` call (per the Global Constraints' verification note), replace it with two separate calls instead:

```elixir
defmodule NewApiApp.CQRS.Reservation.Router do
  use Commanded.Commands.Router

  dispatch(NewApiApp.CQRS.Reservation.Commands.Reserve,
    to: NewApiApp.CQRS.Reservation,
    identity: :reservation_id
  )

  dispatch(NewApiApp.CQRS.Reservation.Commands.Release,
    to: NewApiApp.CQRS.Reservation,
    identity: :reservation_id
  )
end
```

- [ ] **Step 5: Create `lib/new_api_app/cqrs/app.ex`**

```elixir
defmodule NewApiApp.CQRS.App do
  use Commanded.Application, otp_app: :new_api_app

  router(NewApiApp.CQRS.Reservation.Router)
end
```

- [ ] **Step 6: Add the CQRS.App config block to `config/config.exs`**

Extend the SAME contiguous pre-`import_config` block Task 1 started (insert right after Task 1's `NewApiApp.EventStore` config, still before `import_config`, nothing else in the file touched):

```elixir
# Configure the CQRS event store
config :new_api_app, NewApiApp.EventStore,
  serializer: Commanded.Serialization.JsonSerializer,
  username: "postgres",
  password: "postgres",
  database: "new_api_app_eventstore_#{config_env()}",
  hostname: "localhost"

# Configure the CQRS Commanded application
config :new_api_app, NewApiApp.CQRS.App,
  event_store: [
    adapter: Commanded.EventStore.Adapters.EventStore,
    event_store: NewApiApp.EventStore
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
```

- [ ] **Step 7: Add the InMemory override to `config/test.exs`**

Append at the end of `priv/meta/cqrs_component/config/test.exs`:

```elixir

# The plugin's own shipped tests (and a generated project's default test
# suite) use Commanded's in-memory event store adapter — no real Postgres
# event store needed. Dev/prod use the real adapter configured in
# config/config.exs.
config :new_api_app, NewApiApp.CQRS.App,
  event_store: [adapter: Commanded.EventStore.Adapters.InMemory]
```

- [ ] **Step 8: Write `test/cqrs/reservation_test.exs`**

```elixir
defmodule NewApiApp.CQRS.ReservationTest do
  use ExUnit.Case, async: false

  alias Commanded.EventStore.Adapters.InMemory
  alias NewApiApp.CQRS.App
  alias NewApiApp.CQRS.Reservation.Commands.Release
  alias NewApiApp.CQRS.Reservation.Commands.Reserve

  setup do
    start_supervised!(App)
    InMemory.reset!(App)
    :ok
  end

  test "reserving a fresh id succeeds" do
    id = Uniq.UUID.uuid4()
    assert :ok = App.dispatch(%Reserve{reservation_id: id})
  end

  test "reserving an already-reserved id fails" do
    id = Uniq.UUID.uuid4()
    assert :ok = App.dispatch(%Reserve{reservation_id: id})
    assert {:error, :already_reserved} = App.dispatch(%Reserve{reservation_id: id})
  end

  test "releasing a reserved id frees it for a fresh reserve" do
    id = Uniq.UUID.uuid4()
    assert :ok = App.dispatch(%Reserve{reservation_id: id})
    assert :ok = App.dispatch(%Release{reservation_id: id})
    assert :ok = App.dispatch(%Reserve{reservation_id: id})
  end

  test "releasing an id that was never reserved fails" do
    id = Uniq.UUID.uuid4()
    assert {:error, :not_reserved} = App.dispatch(%Release{reservation_id: id})
  end
end
```

If `InMemory.reset!(App)` doesn't match the installed version's real signature (per the Global
Constraints' verification note), try `InMemory.reset!(:new_api_app)` instead, and if
`start_supervised!(App)` doesn't work directly on the `Commanded.Application` module, use
`start_supervised!({App, []})` or consult `Commanded.Application`'s own `child_spec/1` — adjust
and note what actually worked in your report.

- [ ] **Step 9: Run the test**

```bash
cd priv/meta/cqrs_component
mix test test/cqrs/reservation_test.exs
cd -
```

Expected: all 4 tests PASS, no real Postgres/EventStore touched (InMemory adapter only).

- [ ] **Step 10: Commit**

```bash
git add priv/meta/cqrs_component/lib/new_api_app/cqrs/reservation.ex \
        priv/meta/cqrs_component/lib/new_api_app/cqrs/reservation/commands.ex \
        priv/meta/cqrs_component/lib/new_api_app/cqrs/reservation/events.ex \
        priv/meta/cqrs_component/lib/new_api_app/cqrs/reservation/router.ex \
        priv/meta/cqrs_component/lib/new_api_app/cqrs/app.ex \
        priv/meta/cqrs_component/test/cqrs/reservation_test.exs \
        priv/meta/cqrs_component/config/config.exs \
        priv/meta/cqrs_component/config/test.exs
git commit -m "feat(plugin): add NewApiApp.CQRS.Reservation and NewApiApp.CQRS.App"
```

---

### Task 3: Confirm and commit `NewApiApp.CQRS.Cache`

**Files:**
- Verify/keep: `priv/meta/cqrs_component/lib/new_api_app/cqrs/cache.ex` (already exists, uncommitted)

**Interfaces:**
- Produces: `NewApiApp.CQRS.Cache` — consumed by Task 4's `UniqueCheck`.

- [ ] **Step 1: Read the existing file and confirm it matches**

```bash
cat priv/meta/cqrs_component/lib/new_api_app/cqrs/cache.ex
```

It must read exactly:

```elixir
defmodule NewApiApp.CQRS.Cache do
  @moduledoc """
  Fast, non-authoritative pre-check for uniqueness reservations. The
  authoritative guard is NewApiApp.CQRS.Reservation, an event-sourced
  aggregate whose deterministic stream identity makes a duplicate create
  provably fail via the event store's own atomic per-stream append —
  this cache only avoids a wasted round-trip to the event store for the
  common case.
  """

  use Nebulex.Cache, otp_app: :new_api_app, adapter: Nebulex.Adapters.Local
end
```

If it differs (it was drafted for a different, now-superseded design's phrasing), rewrite it to
match exactly.

- [ ] **Step 2: Verify it compiles**

```bash
cd priv/meta/cqrs_component
mix compile --warnings-as-errors
cd -
```

- [ ] **Step 3: Commit**

```bash
git add priv/meta/cqrs_component/lib/new_api_app/cqrs/cache.ex
git commit -m "feat(plugin): confirm NewApiApp.CQRS.Cache for the event-sourced design"
```

---

### Task 4: Rewrite `NewApiApp.CQRS.UniqueCheck`

**Files:**
- Modify (full rewrite): `priv/meta/cqrs_component/lib/new_api_app/cqrs/unique_check.ex`
- Modify (full rewrite): `priv/meta/cqrs_component/test/cqrs/unique_check_test.exs`

**Interfaces:**
- Consumes: `NewApiApp.CQRS.App` (Task 2), `NewApiApp.CQRS.Cache` (Task 3), `NewApiApp.CQRS.Reservation.Commands.{Reserve,Release}` (Task 2).
- Produces: `NewApiApp.CQRS.UniqueCheck.reserve/3`, `.release/3` — consumed by Task 5's `Dispatcher`.

- [ ] **Step 1: Overwrite `lib/new_api_app/cqrs/unique_check.ex` completely**

```elixir
defmodule NewApiApp.CQRS.UniqueCheck do
  @moduledoc """
  Two-layer uniqueness check for a create command's declared unique-field
  groups: a fast Nebulex pre-check, then a race-proof dispatch to
  NewApiApp.CQRS.Reservation at a deterministic stream id. Call reserve/3
  before dispatching the real domain command; on {:error, _} the command
  must not be dispatched. Call release/3 if the domain command's own
  dispatch subsequently fails, to free every group's reservation for a
  retry — event streams are append-only, so "freeing" a ground-truth
  reservation means dispatching Release, not deleting anything; a
  successful create must NEVER call release/3, or the value becomes
  reservable again despite a real entity now holding it.
  """

  alias NewApiApp.CQRS.App
  alias NewApiApp.CQRS.Cache
  alias NewApiApp.CQRS.Reservation.Commands.Release
  alias NewApiApp.CQRS.Reservation.Commands.Reserve

  @ttl :timer.seconds(30)
  @namespace Uniq.UUID.uuid5(:dns, "new_api_app.cqrs.reservation")

  @doc """
  Reserves every field group's key for `schema_tag`/`values`. Returns
  `{:ok, reserved_keys}` if every group was free (both the cache
  pre-check and the Reservation aggregate dispatch succeeded), or
  `{:error, taken_group}` — releasing (cache delete AND a Release
  dispatch) whatever earlier groups this same call had already reserved,
  since the whole multi-group reservation is atomic-or-nothing from the
  caller's point of view.
  """
  @spec reserve(atom(), [[atom()]], map()) :: {:ok, [term()]} | {:error, [atom()]}
  def reserve(schema_tag, unique_fields, values) do
    Enum.reduce_while(unique_fields, {:ok, []}, fn group, {:ok, reserved} ->
      case reserve_group(schema_tag, group, values) do
        {:ok, key} ->
          {:cont, {:ok, [{group, key} | reserved]}}

        :error ->
          Enum.each(reserved, fn {g, key} -> release_group(schema_tag, g, values, key) end)
          {:halt, {:error, group}}
      end
    end)
  end

  @doc """
  Releases every field group's reservation — both the cache key and the
  ground-truth Reservation aggregate (via a Release dispatch). Call this
  only after an aborted create (the real domain command's own dispatch
  failed) — never after a successful one.
  """
  @spec release(atom(), [[atom()]], map()) :: :ok
  def release(schema_tag, unique_fields, values) do
    Enum.each(unique_fields, fn group ->
      release_group(schema_tag, group, values, cache_key(schema_tag, group, values))
    end)
  end

  defp reserve_group(schema_tag, group, values) do
    key = cache_key(schema_tag, group, values)

    case Cache.put_new(key, true, ttl: @ttl) do
      {:ok, false} ->
        :error

      {:ok, true} ->
        reservation_id = reservation_id(schema_tag, group, values)

        case App.dispatch(%Reserve{reservation_id: reservation_id}) do
          :ok -> {:ok, key}
          {:error, :already_reserved} ->
            Cache.delete(key, [])
            :error
        end
    end
  end

  defp release_group(schema_tag, group, values, key) do
    reservation_id = reservation_id(schema_tag, group, values)
    :ok = App.dispatch(%Release{reservation_id: reservation_id})
    Cache.delete(key, [])
  end

  defp cache_key(schema_tag, group, values) do
    {schema_tag, group, Enum.map(group, &Map.fetch!(values, &1))}
  end

  defp reservation_id(schema_tag, group, values) do
    name = :erlang.term_to_binary({schema_tag, group, Enum.map(group, &Map.fetch!(values, &1))})
    Uniq.UUID.uuid5(@namespace, name)
  end
end
```

- [ ] **Step 2: Overwrite `test/cqrs/unique_check_test.exs` completely**

```elixir
defmodule NewApiApp.CQRS.UniqueCheckTest do
  use ExUnit.Case, async: false

  alias Commanded.EventStore.Adapters.InMemory
  alias NewApiApp.CQRS.App
  alias NewApiApp.CQRS.Cache
  alias NewApiApp.CQRS.UniqueCheck

  setup do
    start_supervised!(App)
    start_supervised!(Cache)
    InMemory.reset!(App)
    :ok
  end

  describe "reserve/3" do
    test "reserves every group's key when all groups are free" do
      values = %{
        email: "a-#{System.unique_integer([:positive])}@example.com",
        org_id: 1,
        username: "alice"
      }

      assert {:ok, reserved} = UniqueCheck.reserve(:widget, [[:email], [:org_id, :username]], values)
      assert length(reserved) == 2
    end

    test "fast-rejects and rolls back earlier groups when a later group is taken" do
      taken_username = "taken-#{System.unique_integer([:positive])}"

      first_values = %{
        email: "b1-#{System.unique_integer([:positive])}@example.com",
        org_id: 1,
        username: taken_username
      }

      assert {:ok, _reserved} = UniqueCheck.reserve(:widget, [[:org_id, :username]], first_values)

      email = "b2-#{System.unique_integer([:positive])}@example.com"
      second_values = %{email: email, org_id: 1, username: taken_username}

      assert {:error, [:org_id, :username]} =
               UniqueCheck.reserve(:widget, [[:email], [:org_id, :username]], second_values)

      # The :email group, reserved before the :org_id/:username group lost
      # the race, must have been rolled back — cache AND ground truth —
      # not left dangling.
      retry_values = %{email: email, org_id: 99, username: "someone-else"}
      assert {:ok, _reserved} = UniqueCheck.reserve(:widget, [[:email]], retry_values)
    end
  end

  describe "release/3" do
    test "frees every group's reservation so a later reserve for the same values succeeds" do
      values = %{email: "c-#{System.unique_integer([:positive])}@example.com"}
      unique_fields = [[:email]]

      assert {:ok, _reserved} = UniqueCheck.reserve(:widget, unique_fields, values)
      assert :ok = UniqueCheck.release(:widget, unique_fields, values)
      assert {:ok, _reserved} = UniqueCheck.reserve(:widget, unique_fields, values)
    end
  end
end
```

- [ ] **Step 3: Run the test**

```bash
cd priv/meta/cqrs_component
mix test test/cqrs/unique_check_test.exs
cd -
```

Expected: all 3 tests PASS.

- [ ] **Step 4: Commit**

```bash
git add priv/meta/cqrs_component/lib/new_api_app/cqrs/unique_check.ex \
        priv/meta/cqrs_component/test/cqrs/unique_check_test.exs
git commit -m "feat(plugin): rewrite NewApiApp.CQRS.UniqueCheck for the event-sourced design"
```

---

### Task 5: `NewApiApp.CQRS.Command`, `.Query`, `.Dispatcher`

**Files:**
- Create: `priv/meta/cqrs_component/lib/new_api_app/cqrs/command.ex`
- Create: `priv/meta/cqrs_component/lib/new_api_app/cqrs/query.ex`
- Create: `priv/meta/cqrs_component/lib/new_api_app/cqrs/dispatcher.ex`
- Create: `priv/meta/cqrs_component/test/cqrs/dispatcher_test.exs`

**Interfaces:**
- Consumes: `NewApiApp.CQRS.App` (Task 2), `NewApiApp.CQRS.UniqueCheck.reserve/3`, `.release/3` (Task 4).
- Produces: `NewApiApp.CQRS.Dispatcher.dispatch/2`, `.query/2` — consumed by Task 10's real-EventStore integration test.

- [ ] **Step 1: Create `lib/new_api_app/cqrs/command.ex`**

```elixir
defmodule NewApiApp.CQRS.Command do
  @moduledoc """
  The contract a CQRS command module implements. `build/1` returns a
  plain command struct (no Ecto.Changeset involved) — command
  validation, if any, is the developer's own concern inside `build/1` or
  the aggregate's own `execute/2`. `unique_fields/0` and `schema_tag/0`
  feed NewApiApp.CQRS.UniqueCheck.
  """

  @callback build(params :: map()) :: struct()
  @callback schema_tag() :: atom()
  @callback unique_fields() :: [[atom()]]
end
```

- [ ] **Step 2: Create `lib/new_api_app/cqrs/query.ex`**

```elixir
defmodule NewApiApp.CQRS.Query do
  @moduledoc """
  The contract a CQRS query module implements. No caching, no
  uniqueness — `run/1` is a direct pass-through, dispatched only so
  callers have one entry point (`NewApiApp.CQRS.Dispatcher`) for both
  commands and queries.
  """

  @callback run(params :: map()) :: {:ok, term()} | {:error, term()}
end
```

- [ ] **Step 3: Create `lib/new_api_app/cqrs/dispatcher.ex`**

```elixir
defmodule NewApiApp.CQRS.Dispatcher do
  @moduledoc """
  Single entry point for CQRS commands and queries. dispatch/2 does NOT
  return the created struct (event sourcing decouples persisting an
  event from projecting a read model) — it returns :ok | {:error,
  reason}, matching Commanded.Application.dispatch/2's own contract.
  Fetch the resulting read-model row separately via query/2, after
  dispatch/2 returns :ok.
  """

  alias NewApiApp.CQRS.App
  alias NewApiApp.CQRS.UniqueCheck

  @doc """
  `command_module` must implement `NewApiApp.CQRS.Command`. Reserves
  every unique-field group (see UniqueCheck) before forwarding to
  NewApiApp.CQRS.App.dispatch/2 with consistency: :strong, so a caller
  that immediately calls query/2 after :ok sees the projected row.
  """
  @spec dispatch(module(), map()) :: :ok | {:error, term()}
  def dispatch(command_module, params) do
    command = command_module.build(params)
    # Unique-field values come from the BUILT command struct, not the
    # raw `params` input — build/1 may normalize (cast types, trim,
    # downcase an email, etc.), and the reservation must match what
    # actually gets dispatched, or a normalization difference could let
    # a duplicate through.
    values = Map.from_struct(command)

    case UniqueCheck.reserve(command_module.schema_tag(), command_module.unique_fields(), values) do
      {:ok, _reserved} ->
        case App.dispatch(command, consistency: :strong) do
          :ok ->
            :ok

          {:error, reason} ->
            UniqueCheck.release(command_module.schema_tag(), command_module.unique_fields(), values)
            {:error, reason}
        end

      {:error, taken_group} ->
        {:error, {:already_taken, taken_group}}
    end
  end

  @spec query(module(), map()) :: {:ok, term()} | {:error, term()}
  def query(query_module, params), do: query_module.run(params)
end
```

- [ ] **Step 4: Create the shipped test `test/cqrs/dispatcher_test.exs`**

This test is deliberately DB/domain-aggregate-free: it only exercises the fast-reject path
(`UniqueCheck.reserve/3` failing before `Dispatcher` ever calls `App.dispatch/2` on the fixture
command) — `CreateFixture` is never registered with any Router, so it must never actually be
dispatched. The full success path (a real domain command actually reaching a real aggregate and
projecting a row) is proven only by Task 10's real-EventStore integration test, which is the only
place a real Router/aggregate for a test command is allowed to exist.

```elixir
defmodule NewApiApp.CQRS.DispatcherTest do
  use ExUnit.Case, async: false

  alias Commanded.EventStore.Adapters.InMemory
  alias NewApiApp.CQRS.App
  alias NewApiApp.CQRS.Cache
  alias NewApiApp.CQRS.Dispatcher
  alias NewApiApp.CQRS.UniqueCheck

  defmodule CreateFixture do
    @behaviour NewApiApp.CQRS.Command

    defstruct [:email]

    @impl true
    def build(params), do: %__MODULE__{email: params.email}

    @impl true
    def schema_tag, do: :fixture

    @impl true
    def unique_fields, do: [[:email]]
  end

  setup do
    start_supervised!(App)
    start_supervised!(Cache)
    InMemory.reset!(App)
    :ok
  end

  test "a command whose unique field is already reserved is fast-rejected" do
    email = "taken-#{System.unique_integer([:positive])}@example.com"
    assert {:ok, _reserved} = UniqueCheck.reserve(:fixture, [[:email]], %{email: email})

    assert {:error, {:already_taken, [:email]}} = Dispatcher.dispatch(CreateFixture, %{email: email})
  end
end
```

- [ ] **Step 5: Run the test**

```bash
cd priv/meta/cqrs_component
mix test test/cqrs/dispatcher_test.exs
cd -
```

Expected: PASS.

- [ ] **Step 6: Run every shipped `test/cqrs/` test together**

```bash
cd priv/meta/cqrs_component
mix test test/cqrs/
cd -
```

Expected: all tests across `reservation_test.exs`, `unique_check_test.exs`, and
`dispatcher_test.exs` PASS together (no cross-file InMemory state leakage — each file's own
`setup` calls `InMemory.reset!/1`).

- [ ] **Step 7: Commit**

```bash
git add priv/meta/cqrs_component/lib/new_api_app/cqrs/command.ex \
        priv/meta/cqrs_component/lib/new_api_app/cqrs/query.ex \
        priv/meta/cqrs_component/lib/new_api_app/cqrs/dispatcher.ex \
        priv/meta/cqrs_component/test/cqrs/dispatcher_test.exs
git commit -m "feat(plugin): add NewApiApp.CQRS.Command/Query/Dispatcher"
```

---

### Task 6: Wire the application — supervision, and the README worked example

**Files:**
- Modify: `priv/meta/cqrs_component/lib/new_api_app/application.ex`
- Modify: `priv/meta/cqrs_component/README.md`

**Interfaces:**
- Consumes: `NewApiApp.EventStore` (Task 1), `NewApiApp.CQRS.App` (Task 2), `NewApiApp.CQRS.Cache` (Task 3).
- Produces: a fully self-running `cqrs_component`, ready for Task 7's `derive`.

- [ ] **Step 1: Append the three supervision children**

Change ONLY the `children` list (nothing else in the file) to append all three, in this order, as
the literal last elements:

```elixir
    children = [
      NewApiAppWeb.Telemetry,
      NewApiApp.Repo,
      {DNSCluster, query: Application.get_env(:new_api_app, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: NewApiApp.PubSub},
      # Start a worker by calling: NewApiApp.Worker.start_link(arg)
      # {NewApiApp.Worker, arg},
      # Start to serve requests, typically the last entry
      NewApiAppWeb.Endpoint,
      NewApiApp.EventStore,
      NewApiApp.CQRS.App,
      NewApiApp.CQRS.Cache
    ]
```

Per the Global Constraints, this WILL fall back to a `:manual` anchor once derived (three children
added, not one) — this is expected, do not try to make it look like a single-child edit.

- [ ] **Step 2: Append the README section**

Add to the end of `priv/meta/cqrs_component/README.md`:

````markdown
## CQRS

`NewApiApp.CQRS.Dispatcher.dispatch/2` runs a command through a real, event-sourced pipeline:
build and validate a command struct, reserve its declared unique-field groups (a fast Nebulex
pre-check, then a race-proof dispatch to an internal `NewApiApp.CQRS.Reservation` aggregate),
then dispatch the real domain command through `NewApiApp.CQRS.App`. `dispatch/2` returns
`:ok | {:error, reason}` — **not** the created struct, since persisting an event and projecting
a read model are decoupled. Fetch the result with `NewApiApp.CQRS.Dispatcher.query/2` after
`:ok`.

### Setup

A real EventStore needs its own Postgres database, separate from the app's normal one — run once
per environment:

```bash
mix event_store.create
mix event_store.init
```

(`config/test.exs` already configures the plugin's own tests and a generated project's default
test suite to use Commanded's in-memory adapter instead — no event store setup needed for `mix
test`.)

### Worked example

A command module implements `NewApiApp.CQRS.Command`, its own aggregate implements Commanded's
`execute/2`/`apply/2` contract, and an event handler projects into your own Ecto schema:

```elixir
# A developer's own aggregate, commands, and events — NOT shipped by this plugin.
defmodule NewApiApp.Widgets.Widget do
  defstruct [:id, :email]
end

defmodule NewApiApp.Widgets.Commands.CreateWidget do
  @behaviour NewApiApp.CQRS.Command

  @enforce_keys [:id, :email]
  defstruct [:id, :email]

  @impl true
  def build(params), do: %__MODULE__{id: Uniq.UUID.uuid7(), email: params.email}

  @impl true
  def schema_tag, do: :widget

  @impl true
  def unique_fields, do: [[:email]]
end

defmodule NewApiApp.Widgets.Commands.UpdateWidget do
  @enforce_keys [:id, :email]
  defstruct [:id, :email]
end

defmodule NewApiApp.Widgets.Events.WidgetCreated do
  @enforce_keys [:id, :email]
  defstruct [:id, :email]
end

defmodule NewApiApp.Widgets.Events.WidgetUpdated do
  @enforce_keys [:id, :email]
  defstruct [:id, :email]
end

defmodule NewApiApp.Widgets.Widget do
  defstruct [:id, :email]

  alias NewApiApp.Widgets.Commands.CreateWidget
  alias NewApiApp.Widgets.Commands.UpdateWidget
  alias NewApiApp.Widgets.Events.WidgetCreated
  alias NewApiApp.Widgets.Events.WidgetUpdated

  def execute(%__MODULE__{id: nil}, %CreateWidget{} = cmd) do
    %WidgetCreated{id: cmd.id, email: cmd.email}
  end

  def execute(%__MODULE__{id: id} = _state, %UpdateWidget{} = cmd) when not is_nil(id) do
    %WidgetUpdated{id: cmd.id, email: cmd.email}
  end

  def apply(state, %WidgetCreated{id: id, email: email}) do
    %__MODULE__{state | id: id, email: email}
  end

  def apply(state, %WidgetUpdated{email: email}) do
    %__MODULE__{state | email: email}
  end
end

defmodule NewApiApp.Widgets.Router do
  use Commanded.Commands.Router

  dispatch([NewApiApp.Widgets.Commands.CreateWidget, NewApiApp.Widgets.Commands.UpdateWidget],
    to: NewApiApp.Widgets.Widget,
    identity: :id
  )
end

# Add this Router to NewApiApp.CQRS.App alongside the shipped Reservation.Router:
#
#   defmodule NewApiApp.CQRS.App do
#     use Commanded.Application, otp_app: :new_api_app
#
#     router(NewApiApp.CQRS.Reservation.Router)
#     router(NewApiApp.Widgets.Router)
#   end

defmodule NewApiApp.Widgets.Projector do
  use Commanded.Event.Handler,
    application: NewApiApp.CQRS.App,
    name: "widgets_projector",
    consistency: :strong

  alias NewApiApp.Widgets.Events.WidgetCreated
  alias NewApiApp.Widgets.Events.WidgetUpdated

  def handle(%WidgetCreated{id: id, email: email}, _metadata) do
    %NewApiApp.Widgets.WidgetRecord{}
    |> Ecto.Changeset.cast(%{id: id, email: email}, [:id, :email])
    |> NewApiApp.Repo.insert()

    :ok
  end

  def handle(%WidgetUpdated{id: id, email: email}, _metadata) do
    NewApiApp.Repo.get!(NewApiApp.Widgets.WidgetRecord, id)
    |> Ecto.Changeset.cast(%{email: email}, [:email])
    |> NewApiApp.Repo.update()

    :ok
  end
end
```

`NewApiApp.Widgets.WidgetRecord` is your own Ecto schema for the projected read model, with a
matching migration declaring `create unique_index(:widgets, [:email])` (no explicit `:name`
needed — `UniqueCheck` doesn't validate a DB constraint directly in this design; the event
store's atomic per-stream append is the race guard, and the DB unique index here is a normal
data-integrity backstop for the read model itself). Use UUIDv7 for your own entity identity:

```elixir
@primary_key {:id, Uniq.UUID, autogenerate: true, version: 7, type: :binary_id}
```

Dispatch a create or an update through the same entry point:

```elixir
:ok = NewApiApp.CQRS.Dispatcher.dispatch(NewApiApp.Widgets.Commands.CreateWidget, %{email: "a@example.com"})
{:ok, widget} = NewApiApp.CQRS.Dispatcher.query(NewApiApp.Widgets.Queries.GetWidget, %{email: "a@example.com"})
```

**Uniqueness on update:** `UniqueCheck` is only invoked by the create path. An update that
changes a previously-reserved unique field does not automatically re-reserve — call
`NewApiApp.CQRS.UniqueCheck.reserve/3` yourself before dispatching such an update, and release
the old reservation, if your domain needs that guarantee.

**Limitation:** event versioning/upcasting strategies for evolving your own event schemas over an
aggregate's lifetime are your own project's concern — this plugin doesn't prescribe one.
````

- [ ] **Step 3: Verify it compiles**

```bash
cd priv/meta/cqrs_component
mix compile --warnings-as-errors
cd -
```

Expected: compiles cleanly (the README's worked example is documentation only, not compiled code
— this step just confirms `application.ex`'s edit didn't break anything).

- [ ] **Step 4: Commit**

```bash
git add priv/meta/cqrs_component/lib/new_api_app/application.ex \
        priv/meta/cqrs_component/README.md
git commit -m "feat(plugin): wire EventStore/CQRS.App/CQRS.Cache into cqrs_component's application"
```

---

### Task 7: Derive the `:cqrs` manifest and record real baseline hashes

**Files:**
- Create: `priv/meta/meta_cqrs/manifest.exs`, `priv/meta/meta_cqrs/files/*.eex` (all `derive` output — do not hand-author)
- Modify: `priv/baselines.exs` (rewritten by `mix capstone.baseline.record`)

**Interfaces:**
- Consumes: the finished `priv/meta/cqrs_component/` tree (Tasks 1-6).
- Produces: `priv/meta/meta_cqrs/manifest.exs`, consumed by Task 8's round-trip test and Task 9/10's integration tests.

- [ ] **Step 1: Derive**

```bash
mix capstone.plugin.derive cqrs
```

Expected: `wrote priv/meta/meta_cqrs/manifest.exs` plus a file/dep count.

- [ ] **Step 2: Inspect the manifest for correctness**

```bash
cat priv/meta/meta_cqrs/manifest.exs
```

Verify:
- `deps:` contains exactly six entries: `nebulex`, `nebulex_local`, `uniq`, `commanded`,
  `commanded_eventstore_adapter`, `eventstore` (order matching `mix.exs`'s declaration order).
- Every `lib/new_api_app/cqrs/*.ex`, `lib/new_api_app/cqrs/reservation/*.ex`, and
  `lib/new_api_app/event_store.ex` file, plus all three `test/cqrs/*_test.exs` files, appear as
  `{"...", :sole_owner}`.
- `README.md` appears as `{"README.md", :contributes, [...]}`.
- `config/config.exs` appears as `:contributes` with `:before_import` placement — if it fell back
  to `:manual`, re-check Tasks 1/2's config edits for an accidental extra touch to the file and
  redo the affected step before re-running `derive`.
- `config/test.exs` appears as SOME placement mode — document exactly what `derive` produced here
  (per the Global Constraints, this is genuinely new territory; `:manual` is the expected/accepted
  outcome, but confirm it actually anchors correctly rather than assuming).
- `lib/APP/application.ex` appears as a `:manual` entry (per the Global Constraints — three
  children were added, exceeding the single-child auto-detection heuristic). If it somehow shows
  as `:contributes`, that's a pleasant surprise, not a problem — just note the discrepancy from
  what was expected.

- [ ] **Step 3: Re-derive `:cache` too, confirming its manifest is still current**

```bash
mix capstone.plugin.derive cache
git diff --stat priv/meta/meta_cache
```

Expected: no diff (already derived and unmodified since). If there IS a diff, something changed
`cache_component` unexpectedly — investigate before continuing.

- [ ] **Step 4: Record real baseline hashes for every entry**

```bash
mix capstone.baseline.record
```

This rewrites `priv/baselines.exs` and writes snapshot archives to the repo root
(`<key>_<version>_<sha8>.tar.gz`, NOT gitignored). Confirm they exist:

```bash
ls *_*.tar.gz
```

- [ ] **Step 5: Verify `priv/baselines.exs`'s `:cqrs` entry looks sane**

```bash
mix run -e '
entry = Capstone.Baseline.read!("priv/baselines.exs").cqrs
IO.inspect(entry.derived_from)
IO.inspect(map_size(entry.files))
IO.inspect(entry.path)
'
```

Expected: `:api`, a file count matching the manifest's file count plus every unchanged baseline
file, `"priv/meta/cqrs_component"`.

- [ ] **Step 6: Commit (leave the root snapshot archives untracked for Task 11)**

```bash
git add priv/meta/meta_cqrs priv/meta/meta_cache priv/baselines.exs
git status --porcelain  # confirm the *_*.tar.gz files show as untracked (??), not staged
git commit -m "feat(plugin): derive the :cqrs manifest, record real baseline hashes"
```

---

### Task 8: Round-trip test for `:cqrs`

**Files:**
- Create: `test/capstone/plugin/cqrs_round_trip_test.exs`

**Interfaces:**
- Consumes: `priv/meta/meta_cqrs/manifest.exs`, `priv/meta/cqrs_component/` (Task 7).

- [ ] **Step 1: Write the test file**

Modeled on `test/capstone/plugin/round_trip_test.exs`, WITH the subdirectory-rename fix already
baked into the "differently named project" fixture from the start (that test's older,
incomplete-rename version was a real bug discovered and fixed earlier on this branch — this test
must not repeat it).

```elixir
defmodule Capstone.Plugin.CqrsRoundTripTest do
  # async: false — copies real trees under priv/meta.
  use ExUnit.Case, async: false

  alias Capstone.Baseline
  alias Capstone.Plugin.Apply

  @baseline "priv/meta/baseline_api"
  @plugin "priv/meta/meta_cqrs"
  @raw "priv/meta/cqrs_component"

  setup do
    target = Path.join(System.tmp_dir!(), "cqrs-round-trip-#{System.unique_integer([:positive])}")
    File.cp_r!(@baseline, target)
    on_exit(fn -> File.rm_rf!(target) end)

    {:ok, target: target}
  end

  test "applying meta_cqrs to baseline_api reproduces cqrs_component", %{target: target} do
    {:ok, _component} = Apply.run(@plugin, target)

    expected = Baseline.tree(@raw)
    actual = Baseline.tree(target)

    differing = for {path, hash} <- expected, actual[path] != hash, do: path

    assert differing == []
    assert Enum.sort(Map.keys(actual)) == Enum.sort(Map.keys(expected))
  end

  test "applying twice is a no-op", %{target: target} do
    {:ok, _} = Apply.run(@plugin, target)
    once = Baseline.tree(target)

    {:ok, _} = Apply.run(@plugin, target)

    assert Baseline.tree(target) == once
  end

  test "the plugin installs into a differently named project" do
    other = Path.join(System.tmp_dir!(), "cqrs-other-#{System.unique_integer([:positive])}")
    File.cp_r!(@baseline, other)
    on_exit(fn -> File.rm_rf!(other) end)

    mix = Path.join(other, "mix.exs")
    File.write!(mix, String.replace(File.read!(mix), ":new_api_app", ":other_app"))

    root = Path.join(other, "lib/new_api_app.ex")

    File.write!(
      Path.join(other, "lib/other_app.ex"),
      String.replace(File.read!(root), "NewApiApp", "OtherApp")
    )

    File.rm!(root)

    # A real `mix new other_app` also renames the app's own lib/<app>/
    # subdirectory and rewrites the module name inside each file — this
    # plugin's application.ex edit needs lib/APP/application.ex to exist
    # at the renamed path.
    File.rename!(Path.join(other, "lib/new_api_app"), Path.join(other, "lib/other_app"))

    for file <- Path.wildcard(Path.join(other, "lib/other_app/**/*.ex")) do
      File.write!(file, String.replace(File.read!(file), "NewApiApp", "OtherApp"))
    end

    {:ok, _} = Apply.run(@plugin, other)

    assert File.read!(Path.join(other, "lib/other_app/cqrs/dispatcher.ex")) =~
             "defmodule OtherApp.CQRS.Dispatcher"

    refute File.exists?(Path.join(other, "lib/new_api_app/cqrs/dispatcher.ex"))
  end
end
```

This test intentionally has only 3 cases, not `round_trip_test.exs`'s 5 — `:cqrs` has no
`:manual`-placed file the way `:cache`'s `lib/APP.ex` delegate is, so there's no natural "the
`:manual` hunk is placed, not marked" / "an anchor that cannot be located marks instead of
guessing" scenario for a `lib/APP.ex`-style file here. If Task 7's manifest inspection found
`config/test.exs` fell back to `:manual`, add a 4th test mirroring `round_trip_test.exs`'s
"the `:manual` hunk is placed, not marked" test, pointed at `config/test.exs` instead of
`lib/new_api_app.ex`, before continuing — and if `application.ex` itself needs its own placement
verification given it's `:manual` too, cover that the same way.

- [ ] **Step 2: Run it**

```bash
mix test test/capstone/plugin/cqrs_round_trip_test.exs
```

Expected: all tests PASS. If "applying meta_cqrs to baseline_api reproduces cqrs_component"
fails, the failure names the differing file path — that's `derive`'s own auto-detection either
dropping a hunk or misclassifying a placement mode; re-check Task 7 Step 2's manifest inspection
rather than patching this test to match a wrong reproduction.

- [ ] **Step 3: Commit**

```bash
git add test/capstone/plugin/cqrs_round_trip_test.exs
git commit -m "test(plugin): add a round-trip test for the event-sourced :cqrs plugin"
```

---

### Task 9: `:cqrs` structural toolchain tests (including composing with `:cache`)

**Files:**
- Modify: `test/integration/plugin_lifecycle_test.exs`

**Interfaces:**
- Consumes: `priv/baselines.exs`'s `:cqrs` entry, `priv/meta/meta_cqrs/manifest.exs` (Task 7).

Per the Global Constraints, this task's `--include toolchain` tests need the local-packaging
workaround BEFORE Task 11 publishes: run `mix capstone.plugin.package cqrs` and
`mix capstone.plugin.package cache`, then copy both resulting archives from `priv/plugins/` into
`~/Library/Caches/capstone/plugins/` — do this once before Step 2, not per test.

- [ ] **Step 1: Add the new `:cqrs` and `:cache`+`:cqrs` toolchain tests**

Insert these tests into `test/integration/plugin_lifecycle_test.exs`, after the existing `:cache`
test (before the `assert_placed_not_marked/3` helper's `defp`):

```elixir
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
    assert application =~ "WithCqrs.EventStore"
    assert application =~ "WithCqrs.CQRS.App"
    assert application =~ "WithCqrs.CQRS.Cache"

    Shell.cmd!(["compile"], project)
  end

  # The design spec's "Composability with :cache" section claims :cqrs and
  # :cache can both be applied to one project without conflict — this is
  # the only test that actually applies both together and proves it.
  @tag :toolchain
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
    assert application =~ "WithCacheAndCqrs.EventStore"
    assert application =~ "WithCacheAndCqrs.CQRS.App"
    assert application =~ "WithCacheAndCqrs.CQRS.Cache"

    config = File.read!(Path.join(project, "config/config.exs"))
    assert config =~ "WithCacheAndCqrs.Cache.Store"
    assert config =~ "WithCacheAndCqrs.EventStore"
    assert config =~ "WithCacheAndCqrs.CQRS.App"

    Shell.cmd!(["compile"], project)

    # config/test.exs already overrides CQRS.App to the InMemory adapter,
    # so this genuinely starts the whole supervision tree — including the
    # real, Nebulex-backed :cache Store — without needing a real
    # Postgres-backed event store.
    output =
      Shell.cmd!(
        ["run", "-e", "{:ok, _} = Application.ensure_all_started(:with_cache_and_cqrs)"],
        project
      )

    refute output =~ "error"
  end
```

- [ ] **Step 2: Run them**

```bash
mix test test/integration/plugin_lifecycle_test.exs --include toolchain --only test:"mix capstone.new applies plugins: [:cqrs] from target.exs"
mix test test/integration/plugin_lifecycle_test.exs --include toolchain --only test:"mix capstone.new applies plugins: [:cache, :cqrs] together without conflict"
```

If the `--only test:"..."` name filter syntax isn't supported by this project's `mix test` setup
(per the earlier discovery that `-k` isn't valid here), use `--include toolchain` together with
the file:line form instead, matching the pattern already used for the `:cache` toolchain test.

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add test/integration/plugin_lifecycle_test.exs
git commit -m "test(plugin): add structural toolchain tests for :cqrs and :cache+:cqrs composition"
```

---

### Task 10: Real EventStore/Postgres integration test

**Files:**
- Create: `test/integration/cqrs_dispatch_test.exs`

**Interfaces:**
- Consumes: `NewApiApp.CQRS.Dispatcher.dispatch/2`, `.query/2`, `NewApiApp.CQRS.UniqueCheck.validate` semantics, `NewApiApp.CQRS.Cache.delete/2` — all as templated into a real generated project (Tasks 1-9).

Per the Global Constraints, this test's fixture aggregate, commands, events, Router, projector,
Ecto schema, and migration are written directly into a freshly bootstrapped TEMP project, never
into `priv/meta/cqrs_component/`.

- [ ] **Step 1: Confirm Postgres is reachable**

```bash
pg_isready -h localhost
```

- [ ] **Step 2: Write the test file**

```elixir
defmodule Capstone.Integration.CqrsDispatchTest do
  @moduledoc """
  Exercises the full :cqrs dispatch path against a real, Postgres-backed
  EventStore: a successful create whose projection is visible immediately
  (consistency: :strong), a genuine concurrent race (proving the
  Reservation aggregate's deterministic id + the event store's atomic
  per-stream append serializes it), and a duplicate dispatch after the
  Nebulex cache reservation has been deleted (proving the Reservation
  aggregate, not the cache, is the real ground truth).

  The fixture schema, migration, aggregate, commands, events, Router, and
  projector written here into the GENERATED project are NOT part of
  priv/meta/cqrs_component/ — capstone doesn't know a consuming project's
  domain, so this lives entirely in this repo's own test suite.
  """

  use ExUnit.Case, async: false

  alias Capstone.New.Bootstrap
  alias Capstone.New.Options
  alias Capstone.New.Shell

  setup do
    Mix.Local.append_archives()
    Mix.Task.reenable("new")
    Mix.Task.reenable("phx.new")

    dir = Path.join(System.tmp_dir!(), "cqrs-dispatch-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, tmp_dir: dir}
  end

  @tag :toolchain
  test "dispatch: success, a concurrent race, and the aggregate catching what the cache no longer blocks",
       %{tmp_dir: tmp} do
    capstone_path = File.cwd!()
    name = "cqrs_dispatch"

    opts = %Options{
      name: name,
      app: :cqrs_dispatch,
      module: CqrsDispatch,
      base: :api,
      github_org: "acme",
      capstone: {:path, capstone_path},
      plugins: [:cqrs]
    }

    File.cd!(tmp, fn -> assert :ok = Bootstrap.run(opts, Bootstrap.defaults()) end)

    project = Path.join(tmp, name)
    write_fixture_migration!(project)
    write_fixture_domain!(project)
    write_fixture_router_wiring!(project)
    write_fixture_test!(project)

    Shell.cmd!(["event_store.create"], project)
    Shell.cmd!(["event_store.init"], project)
    Shell.cmd!(["test", "test/widget_dispatch_test.exs"], project)
    Shell.cmd!(["event_store.drop"], project)
    Shell.cmd!(["ecto.drop", "--quiet"], project)
  end

  defp write_fixture_migration!(project) do
    path = Path.join(project, "priv/repo/migrations/20260828000001_create_widgets.exs")
    File.mkdir_p!(Path.dirname(path))

    File.write!(path, """
    defmodule CqrsDispatch.Repo.Migrations.CreateWidgets do
      use Ecto.Migration

      def change do
        create table(:widgets, primary_key: false) do
          add :id, :binary_id, primary_key: true
          add :email, :string, null: false

          timestamps(type: :utc_datetime)
        end

        create unique_index(:widgets, [:email])
      end
    end
    """)
  end

  defp write_fixture_domain!(project) do
    File.write!(Path.join(project, "lib/cqrs_dispatch/widgets.ex"), """
    defmodule CqrsDispatch.WidgetRecord do
      use Ecto.Schema

      @primary_key {:id, Uniq.UUID, autogenerate: false, version: 7, type: :binary_id}
      schema "widgets" do
        field :email, :string
        timestamps(type: :utc_datetime)
      end
    end

    defmodule CqrsDispatch.Widgets.Commands.CreateWidget do
      @behaviour CqrsDispatch.CQRS.Command

      @enforce_keys [:id, :email]
      defstruct [:id, :email]

      @impl true
      def build(params), do: %__MODULE__{id: Uniq.UUID.uuid7(), email: params.email}

      @impl true
      def schema_tag, do: :widget

      @impl true
      def unique_fields, do: [[:email]]
    end

    defmodule CqrsDispatch.Widgets.Events.WidgetCreated do
      @enforce_keys [:id, :email]
      defstruct [:id, :email]
    end

    defmodule CqrsDispatch.Widgets.Widget do
      defstruct [:id, :email]

      alias CqrsDispatch.Widgets.Commands.CreateWidget
      alias CqrsDispatch.Widgets.Events.WidgetCreated

      def execute(%__MODULE__{id: nil}, %CreateWidget{} = cmd) do
        %WidgetCreated{id: cmd.id, email: cmd.email}
      end

      def apply(state, %WidgetCreated{id: id, email: email}) do
        %__MODULE__{state | id: id, email: email}
      end
    end

    defmodule CqrsDispatch.Widgets.Router do
      use Commanded.Commands.Router

      dispatch(CqrsDispatch.Widgets.Commands.CreateWidget,
        to: CqrsDispatch.Widgets.Widget,
        identity: :id
      )
    end

    defmodule CqrsDispatch.Widgets.Projector do
      use Commanded.Event.Handler,
        application: CqrsDispatch.CQRS.App,
        name: "widgets_projector",
        consistency: :strong

      alias CqrsDispatch.Widgets.Events.WidgetCreated

      def handle(%WidgetCreated{id: id, email: email}, _metadata) do
        %CqrsDispatch.WidgetRecord{}
        |> Ecto.Changeset.cast(%{id: id, email: email}, [:id, :email])
        |> CqrsDispatch.Repo.insert()

        :ok
      end
    end
    """)
  end

  defp write_fixture_router_wiring!(project) do
    app_path = Path.join(project, "lib/cqrs_dispatch/cqrs/app.ex")

    File.write!(app_path, """
    defmodule CqrsDispatch.CQRS.App do
      use Commanded.Application, otp_app: :cqrs_dispatch

      router(CqrsDispatch.CQRS.Reservation.Router)
      router(CqrsDispatch.Widgets.Router)
    end
    """)

    application_path = Path.join(project, "lib/cqrs_dispatch/application.ex")
    original = File.read!(application_path)

    updated =
      String.replace(
        original,
        "CqrsDispatch.CQRS.Cache\n    ]",
        "CqrsDispatch.CQRS.Cache,\n      CqrsDispatch.Widgets.Projector\n    ]"
      )

    # String.replace/3 is a no-op (not an error) if the pattern doesn't
    # match — assert the file actually changed, or a whitespace mismatch
    # here would silently leave the Projector unsupervised instead of
    # failing loudly.
    if updated == original do
      raise "expected to find \"CqrsDispatch.CQRS.Cache\\n    ]\" in #{application_path}, but it wasn't there — inspect the file's actual content and adjust the replace pattern"
    end

    File.write!(application_path, updated)
  end

  defp write_fixture_test!(project) do
    File.write!(Path.join(project, "test/widget_dispatch_test.exs"), """
    defmodule CqrsDispatch.WidgetDispatchTest do
      use CqrsDispatch.DataCase, async: false

      alias CqrsDispatch.CQRS.Cache
      alias CqrsDispatch.CQRS.Dispatcher
      alias CqrsDispatch.Widgets.Commands.CreateWidget

      test "a successful create is visible immediately via query" do
        email = "widget-\#{System.unique_integer([:positive])}@example.com"
        assert :ok = Dispatcher.dispatch(CreateWidget, %{email: email})

        widget = CqrsDispatch.Repo.get_by!(CqrsDispatch.WidgetRecord, email: email)
        assert widget.email == email
      end

      test "two concurrent dispatches for the same email: exactly one succeeds" do
        email = "race-\#{System.unique_integer([:positive])}@example.com"

        results =
          [Task.async(fn -> Dispatcher.dispatch(CreateWidget, %{email: email}) end),
           Task.async(fn -> Dispatcher.dispatch(CreateWidget, %{email: email}) end)]
          |> Enum.map(&Task.await(&1, 5_000))

        assert Enum.count(results, &(&1 == :ok)) == 1
        assert Enum.count(results, &match?({:error, _}, &1)) == 1
      end

      test "the Reservation aggregate, not the cache, is the real ground truth" do
        email = "expired-\#{System.unique_integer([:positive])}@example.com"
        assert :ok = Dispatcher.dispatch(CreateWidget, %{email: email})

        # Simulate the cache reservation having expired (or never existed,
        # e.g. after a node restart) — the cache no longer blocks a second
        # attempt, so this proves the Reservation aggregate's own
        # deterministic identity is the actual ground truth, not the cache.
        key = {:widget, [:email], [email]}
        Cache.delete(key, [])

        assert {:error, {:already_taken, [:email]}} = Dispatcher.dispatch(CreateWidget, %{email: email})
      end
    end
    """)
  end
end
```

- [ ] **Step 3: Run it**

```bash
mix test test/integration/cqrs_dispatch_test.exs --include toolchain
```

Expected: PASS. This is the slowest test in the plan (a full `mix capstone.new` + `deps.get` +
`deps.compile` + `event_store.create/init` + `ecto.create/migrate` + `mix test` round trip) —
budget several minutes. If the concurrent-race test is ever flaky (both dispatches occasionally
succeed, or both fail), that means the Reservation aggregate's atomicity assumption is wrong for
the configured EventStore adapter — re-check the real EventStore adapter's actual per-stream
append guarantee before assuming it's a test bug.

- [ ] **Step 4: Commit**

```bash
git add test/integration/cqrs_dispatch_test.exs
git commit -m "test(plugin): add a real-EventStore dispatch test proving the cache/aggregate uniqueness split"
```

---

### Task 11: Package, publish, and run the full gate suite

**Files:** none new — packaging and verification only.

- [ ] **Step 1: Run the full local gate suite**

```bash
mix format --check-formatted
mix credo --strict
mix dialyzer
mix doctor
mix coveralls
mix test --include toolchain
```

Fix anything that fails before continuing. None of Tasks 1-10 added code under this repo's own
`lib/` (everything new lives under `priv/meta/`, which is data, not compiled capstone source), so
`mix coveralls`' baseline should be unaffected — if it drops, something leaked into `lib/` that
shouldn't have.

- [ ] **Step 2: Package both plugins**

```bash
mix capstone.plugin.package cache
mix capstone.plugin.package cqrs
```

Expected: `wrote priv/plugins/cache-<elixir>-<capstone>-<sha>.tar.gz` and
`wrote priv/plugins/cqrs-<elixir>-<capstone>-<sha>.tar.gz`. Confirm nothing new is staged:

```bash
git status --porcelain priv/plugins/
```

- [ ] **Step 3: Determine the current version and create a GitHub release**

```bash
version=$(cat .version)
echo "$version"
gh release create "v$version" \
  --repo wimwian-org/capstone \
  --title "v$version" \
  --notes "Real Nebulex-backed :cache, and a new event-sourced :cqrs plugin (commanded + eventstore, a Reservation aggregate for race-proof uniqueness, UUIDv7 entity identity)." \
  --target dev
```

If a release for this exact version tag already exists, use `gh release upload "v$version" <files>`
against the existing release instead of `gh release create`.

- [ ] **Step 4: Upload both archive sets**

```bash
gh release upload "v$version" ./*_"$version"_*.tar.gz --repo wimwian-org/capstone
gh release upload "v$version" priv/plugins/cache-*.tar.gz priv/plugins/cqrs-*.tar.gz --repo wimwian-org/capstone
```

- [ ] **Step 5: Clean up the untracked root-level snapshot archives**

```bash
rm -f ./*_"$version"_*.tar.gz
git status --porcelain
```

Expected: clean.

- [ ] **Step 6: Final sanity check — verify both plugins download and apply from the release**

```bash
rm -rf ~/Library/Caches/capstone
mix run -e '
dir = Capstone.Plugin.Registry.default_dir()
Capstone.Plugin.Remote.sync!(:cache, dir)
Capstone.Plugin.Remote.sync!(:cqrs, dir)
IO.inspect(File.ls!(dir))
'
rm -rf ~/Library/Caches/capstone
```

Expected: the listed files include both a `cache-*.tar.gz` and a `cqrs-*.tar.gz` matching the
version just packaged.

- [ ] **Step 7: Final commit if anything changed during gate fixes**

```bash
git status --porcelain
# If clean, nothing to commit.
# If Step 1 required fixes, commit them:
git add -A
git commit -m "chore(plugin): fix gate failures found while finishing the event-sourced :cqrs plugin"
```
