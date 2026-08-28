# `:cqrs` plugin — event-sourced redesign (supersedes the `:cqrs` half of 2026-08-27's spec)

Date: 2026-08-28
Status: approved, pending implementation plan

## Relationship to the prior spec

`docs/superpowers/specs/2026-08-27-cqrs-plugin-design.md` covered two independent changes: fixing
the `:cache` plugin (real, supervised Nebulex cache) and adding a hand-rolled, non-event-sourced
`:cqrs` plugin. The `:cache` fix has already been implemented, tested, and committed
(`priv/meta/cache_component/`, `priv/meta/meta_cache/`) — nothing here changes it.

**This document replaces that spec's entire `:cqrs` plugin section.** The hand-rolled
Command/Query/Dispatcher design (direct `Ecto.Repo.insert`, cache-only uniqueness) is discarded in
favor of real event sourcing built on `commanded` + `eventstore`. Everything under "`:cqrs` plugin"
in the prior spec — including its "Composing with `:cache`" and "Testing" subsections — is
superseded by this document. The prior spec's own `Global Constraints` about UUIDv7
(`@primary_key {:id, Uniq.UUID, autogenerate: true, version: 7, type: :binary_id}`) still applies
to entity aggregates' own identity in this design (see UUID Conventions below), just not to the
new deterministic reservation IDs.

A partial implementation of the old design was started and abandoned mid-task (uncommitted
`priv/meta/cqrs_component/lib/new_api_app/cqrs/cache.ex`, `unique_check.ex`,
`test/cqrs/unique_check_test.exs`) before this redesign was requested — `NewApiApp.CQRS.Cache`
(the Nebulex instance) is reusable as-is in the new design; `UniqueCheck`'s Ecto.Changeset-based
API is not and gets replaced per this document.

## Purpose

Give a generated project a genuine event-sourced CQRS shape: aggregates that persist as event
streams (not directly-inserted rows), commands dispatched through a real command-dispatch pipeline
(`commanded`), and a uniqueness mechanism that survives concurrent dispatch without relying on a
relational unique index (event sourcing has no such index to lean on before a projection runs).

Per goals.md D17 / the plugin-ecosystem design's continuation notes, there is still no
`mix capstone.gen`. The plugin ships reusable, fully generic library modules; a developer writes
their own aggregates, events, commands, and Router against them — same "library modules only"
stance as every other plugin so far, extended here to explicitly include a **complete worked
example in the README** (not shipped as real code in the component tree) so a developer isn't
starting from a blank page against unusually heavy event-sourcing ceremony.

## Dependencies

Added to `priv/meta/cqrs_component/mix.exs`, appended to the existing deps list (which, per Task 3
of the original implementation plan, already carries `{:nebulex, "~> 3.0"}`,
`{:nebulex_local, "~> 3.0"}`, `{:uniq, "~> 0.6"}` from the abandoned prior attempt — all three stay,
still needed):

```elixir
{:commanded, "~> 1.4"},
{:commanded_eventstore_adapter, "~> 1.4"},
{:eventstore, "~> 1.4"}
```

## Architecture overview

```
Client code
   │
   │ builds a command struct, dispatches via Dispatcher
   ▼
NewApiApp.CQRS.Dispatcher.dispatch/2 ──────────────┐
   │                                                │
   │ 1. UniqueCheck.reserve/3 (fast pre-check)      │ delegates the
   │    - Cache.put_new/3 on each unique-field       │ actual command to
   │      group's derived key                        │
   │ 2. UniqueCheck.reserve/3 (ground truth)          │
   │    - dispatch Reserve to NewApiApp.CQRS.App,     │
   │      routed to Reservation aggregate at a        │
   │      DETERMINISTIC stream id (Uniq.UUID.uuid5)   │
   │    - EventStore's atomic per-stream append is    │
   │      the actual race guard                       │
   │ 3. on success, dispatch the real domain command  │
   ▼                                                  ▼
NewApiApp.CQRS.App (Commanded.Application) ──uses──▶ NewApiApp.EventStore (real, Postgres-backed
   │  routers: Reservation.Router (shipped),                          in dev/prod;
   │           <developer's own Router(s)> (not shipped)              InMemory adapter in :test)
   ▼
Domain aggregate (developer-authored) ──applies events──▶ EventStore
                                          │
                                          ▼
                          Event handler (developer-authored, consistency: :strong)
                                          │
                                          ▼
                          Ecto-backed read model (developer's own schema)
                                          │
                                          ▼
                          NewApiApp.CQRS.Dispatcher.query/2 (unchanged pass-through)
```

What capstone ships as real code in `cqrs_component/`:
- `NewApiApp.EventStore` — the EventStore module.
- `NewApiApp.CQRS.App` — the Commanded.Application, wired to the EventStore and to
  `Reservation.Router`.
- `NewApiApp.CQRS.Cache` — the Nebulex reservation cache (fast pre-check), same purpose as the
  prior design.
- `NewApiApp.CQRS.Reservation` — a fully generic aggregate (module, command, event) plus its own
  `Reservation.Router` — capstone's own infrastructure, not domain-specific, so (unlike a
  developer's own aggregate) it *is* shipped as real code.
- `NewApiApp.CQRS.UniqueCheck` — reservation logic (cache pre-check + Reservation dispatch).
- `NewApiApp.CQRS.Dispatcher` — thin wrapper: `dispatch/2` runs the uniqueness flow then forwards
  to `NewApiApp.CQRS.App.dispatch/2`; `query/2` is an unchanged pass-through to a `Query` behaviour
  module, identical in spirit to the prior design.
- `NewApiApp.CQRS.Query` — the query behaviour (unchanged from the prior design: `@callback run/1`).

What capstone does **not** ship (README worked example only): any domain aggregate, its
commands/events, its own Router, or its projecting event handler. These are inherently
domain-specific — capstone doesn't know a consuming project's schemas, same reasoning the prior
spec already established for why no fixture schemas are shipped.

## Modules

### `NewApiApp.EventStore`

```elixir
defmodule NewApiApp.EventStore do
  use EventStore, otp_app: :new_api_app
end
```

Config (`config/config.exs`, before `import_config`, matching the existing auto-detected
placement mechanism):

```elixir
config :new_api_app, NewApiApp.EventStore,
  serializer: Commanded.Serialization.JsonSerializer,
  username: "postgres",
  password: "postgres",
  database: "new_api_app_eventstore_#{config_env()}",
  hostname: "localhost"
```

`Commanded.Serialization.JsonSerializer` (not `EventStore.JsonSerializer`) is required for
Commanded integration — verified against `eventstore`'s own hexdocs, which calls this out
explicitly. The event store's database is intentionally separate from `NewApiApp.Repo`'s own
database (a distinct schema/database is how EventStore isolates its append-only event log from
the application's normal Ecto-managed tables) — named `..._eventstore_#{config_env()}` so dev/test
don't collide.

**Setup steps** (documented in the README contribution, run once per environment, not automated
by capstone — mirrors how `mix ecto.create`/`migrate` are already the developer's own
responsibility for the normal Repo):

```bash
mix event_store.create
mix event_store.init
```

(Real EventStore mix tasks, confirmed against `commanded/eventstore`'s own task modules
(`EventStore.Tasks.Create`, `EventStore.Tasks.Init`, `EventStore.Tasks.Migrate`) — `create`
provisions the database, `init` creates the event store schema/tables within it. `mix
event_store.migrate` is for upgrading an *existing* event store's schema version later, not needed
on first setup.)

### `NewApiApp.CQRS.App`

```elixir
defmodule NewApiApp.CQRS.App do
  use Commanded.Application, otp_app: :new_api_app

  router(NewApiApp.CQRS.Reservation.Router)
end
```

Config (`config/config.exs`, same placement):

```elixir
config :new_api_app, NewApiApp.CQRS.App,
  event_store: [
    adapter: Commanded.EventStore.Adapters.EventStore,
    event_store: NewApiApp.EventStore
  ]
```

Verified against `Commanded.Application`'s own hexdocs: `router/1` may be called multiple times to
register more than one router against the same Application — this is how a developer adds their
own domain Router alongside the shipped `Reservation.Router`, shown in the README worked example:

```elixir
defmodule NewApiApp.CQRS.App do
  use Commanded.Application, otp_app: :new_api_app

  router(NewApiApp.CQRS.Reservation.Router)
  router(NewApiApp.Widgets.Router)   # <- developer adds this line
end
```

`Commanded.Application` also generates its own `dispatch/1,2,3` that forwards to whichever
registered router recognizes the command — `NewApiApp.CQRS.Dispatcher.dispatch/2` (below) calls
`NewApiApp.CQRS.App.dispatch/2` directly rather than reaching into a specific router.

### `NewApiApp.CQRS.Cache`

Unchanged from the abandoned prior attempt:

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

### `NewApiApp.CQRS.Reservation` (aggregate + command + event + router)

All fully generic — capstone's own infrastructure, ships as real code:

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
  never releases it, leaving the reservation permanent (the correct
  behavior — the value is now genuinely, permanently taken by the real
  entity).
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

defmodule NewApiApp.CQRS.Reservation.Commands.Reserve do
  @enforce_keys [:reservation_id]
  defstruct [:reservation_id]
end

defmodule NewApiApp.CQRS.Reservation.Commands.Release do
  @enforce_keys [:reservation_id]
  defstruct [:reservation_id]
end

defmodule NewApiApp.CQRS.Reservation.Events.Reserved do
  @enforce_keys [:reservation_id]
  defstruct [:reservation_id]
end

defmodule NewApiApp.CQRS.Reservation.Events.Released do
  @enforce_keys [:reservation_id]
  defstruct [:reservation_id]
end

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

`identity: :reservation_id` tells Commanded which command field carries the aggregate's stream
id — verified against `Commanded.Commands.Router`'s own hexdocs usage example, which uses the same
`identity:` option to name the field holding the target aggregate's identity. `dispatch/2` accepts
a list of command modules routed to the same aggregate/identity, so `Reserve` and `Release` share
one `dispatch` clause (to be re-confirmed against the router macro's real source during
implementation — see Verification Notes).

**Aggregate state note:** `released: true` is the *initial* state (a fresh aggregate — an
unapplied stream — starts as "not reserved," i.e. released), not applied by any event; it only
flips to `false` once a `Reserved` event has actually been applied, and back to `true` once a
`Released` event has. This makes the initial state and the post-`Released` state identical by
design — dispatching `Reserve` again after a `Release` succeeds, exactly as dispatching it for
the very first time would.

### `NewApiApp.CQRS.UniqueCheck`

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

Note `release_group/4`'s `:ok = App.dispatch(...)` — dispatching `Release` against a reservation
this same flow just created (via `Reserve`) cannot legitimately return `{:error, :not_reserved}`,
since no other process can un-reserve it in between (the Reservation aggregate has no other path
back to `released: true` except this exact dispatch). If that assumption ever proves wrong during
implementation, the match failure is the correct, loud signal of a design bug — not something to
silently rescue.

`Uniq.UUID.uuid5/3` (`uuid5(namespace, name, format \\ :default)`) generates a deterministic
UUID from a namespace UUID and a name — verified against `uniq` 0.6.3's own hexdocs, which
describes it as "generating UUIDs deterministically, given a namespace and a name," per RFC 4122.
`@namespace` is itself a fixed, deterministically-generated uuid5 (from a stable string), so
`reservation_id/3`'s output for the same `{schema_tag, group, values}` is stable across restarts —
required, since the whole mechanism depends on the *same* inputs always producing the *same*
stream id.

### `NewApiApp.CQRS.Dispatcher`

```elixir
defmodule NewApiApp.CQRS.Dispatcher do
  @moduledoc """
  Single entry point for CQRS commands and queries. dispatch/2 no longer
  returns the created struct (event sourcing decouples persisting an
  event from projecting a read model) — it returns :ok | {:error, reason},
  matching Commanded.Application.dispatch/2's own contract. Fetch the
  resulting read-model row separately via query/2, after dispatch/2
  returns :ok.
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
    # Unique-field values are read from the BUILT command struct, not the raw
    # `params` input — build/1 may normalize (cast types, trim, downcase an
    # email, etc.), and the reservation must match what actually gets
    # dispatched, or a normalization difference could let a duplicate through.
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

### `NewApiApp.CQRS.Command` (behaviour, replaces the prior Ecto.Changeset-based one)

```elixir
defmodule NewApiApp.CQRS.Command do
  @moduledoc """
  The contract a CQRS command module implements. Unlike the prior
  design, `build/1` returns a plain command struct (no Ecto.Changeset
  involved) — command validation, if any, is the developer's own
  concern inside `build/1` or the aggregate's own `execute/2`.
  `unique_fields/0` and `schema_tag/0` feed NewApiApp.CQRS.UniqueCheck
  exactly as the prior design's did.
  """

  @callback build(params :: map()) :: struct()
  @callback schema_tag() :: atom()
  @callback unique_fields() :: [[atom()]]
end
```

### `NewApiApp.CQRS.Query` (unchanged)

```elixir
defmodule NewApiApp.CQRS.Query do
  @callback run(params :: map()) :: {:ok, term()} | {:error, term()}
end
```

## UUID conventions

Two distinct, non-interchangeable UUID uses:

- **Entity aggregate identity** (a developer's own `Widget`, `User`, etc.): random, generated
  fresh per create, using `Uniq.UUID.uuid7/1` at command-construction time (client-generates-id,
  standard Commanded practice) — this is the prior spec's UUIDv7 convention, unchanged, and still
  documented in the README as the recommended identity scheme for a developer's own aggregates and
  their eventual Ecto-projected read-model primary keys (`@primary_key {:id, Uniq.UUID,
  autogenerate: true, version: 7, type: :binary_id}` on the read-model schema).
- **Reservation stream identity** (`NewApiApp.CQRS.Reservation`'s own id): deterministic, via
  `Uniq.UUID.uuid5/3`, derived from the unique field group's values — must be the same every time
  for the same values, which UUIDv7 (time-based, random) cannot provide. This is new to this
  design and internal to `UniqueCheck` — a developer never generates one by hand.

## Update support

Lifted from the prior design's create-only limitation. A single aggregate's `execute/2` dispatches
on both its own current state and the incoming command, e.g.:

```elixir
def execute(%Widget{id: nil}, %CreateWidget{} = cmd), do: %WidgetCreated{...}
def execute(%Widget{id: id}, %UpdateWidget{} = cmd) when not is_nil(id), do: %WidgetUpdated{...}
```

dispatched through the same `NewApiApp.CQRS.Dispatcher.dispatch/2`. Uniqueness reservation
(`UniqueCheck`) is only invoked by the create path — an update touching a previously-reserved
unique field does not automatically re-reserve; the README documents this as the developer's own
responsibility to handle (e.g., by calling `UniqueCheck.reserve/3` again inside their own update
command's handling before dispatch, releasing the old reservation), not silently unsupported.

## Wiring

- `mix.exs`: three new deps (Dependencies section above).
- `config/config.exs`: `NewApiApp.EventStore` config block and `NewApiApp.CQRS.App` config block,
  both inserted before `import_config` (same auto-detected `:before_import` placement mechanism
  already proven for `:cache`).
- `config/test.exs`: overrides `NewApiApp.CQRS.App`'s `event_store:` to
  `[adapter: Commanded.EventStore.Adapters.InMemory]` — no real Postgres needed for the plugin's
  own shipped tests or a generated project's default test suite.
- `lib/new_api_app/application.ex`: three new supervision children —
  `NewApiApp.EventStore`, `NewApiApp.CQRS.App`, `NewApiApp.CQRS.Cache` — appended as the last three
  elements of the `children` list. **This is more than the single child the existing
  `added_child/2` auto-detection heuristic supports (Global Constraint: "exactly one child is
  added per component"), so this plugin's `application.ex` entry falls back to a `:manual` anchor**
  in the derived manifest, unlike `:cache`'s clean `:contributes` capture. This is a known,
  accepted consequence of the redesign, not a defect to route around — `Capstone.Plugin.Apply`
  already supports `:manual` anchoring as a first-class placement mode.
- `README.md`: documents `mix event_store.create && mix event_store.init` setup, the full worked
  example (an aggregate, its commands/events, a Router, a `consistency: :strong` event handler
  projecting into an Ecto read model, and both a create and an update dispatch), and the
  uniqueness/update-reservation caveat above.

## Testing

- **Shipped, DB-free unit tests** (`cqrs_component/test/cqrs/`): against `:test` config's
  `Commanded.EventStore.Adapters.InMemory` adapter. Covers: `Reserve` dispatched twice at the same
  deterministic id (second fails with `{:error, :already_reserved}`); `Release` freeing a reserved
  id so a subsequent `Reserve` at that same id succeeds again; `Release` dispatched at an id that
  was never reserved (fails with `{:error, :not_reserved}`); `UniqueCheck.reserve/3`'s success,
  taken-group, and multi-group-rollback paths (a later group failing correctly frees an earlier
  group's reservation, cache AND ground truth, verified by successfully re-reserving it);
  `Dispatcher.dispatch/2`'s cache-then-reservation flow using the `Reservation` aggregate directly
  (no domain aggregate needed, matching the prior design's DB-free shipped-test philosophy — no
  fixture schema, no real Postgres). Each test resets
  `Commanded.EventStore.Adapters.InMemory` state between cases (`reset!/1`, verified against
  commanded's own hexdocs, which documents this exact caveat and API for the InMemory adapter) to
  avoid cross-test leakage from shared in-memory event state — necessary since, unlike Nebulex's
  local adapter, InMemory's default behavior is to retain state process for the test run.
- **Capstone's own real-Postgres integration test** (`test/integration/`, mirroring the prior
  plan's Task 10 in spirit but proving a different mechanism): runs `mix event_store.create && mix
  event_store.init` against a real, freshly-bootstrapped generated project configured for the real
  `Commanded.EventStore.Adapters.EventStore` adapter, then exercises: a successful dispatch whose
  projected read-model row is visible immediately (proving `consistency: :strong` actually blocks
  until the projection lands); two concurrent dispatches for the same unique value (proving the
  Reservation aggregate's deterministic id + the real EventStore's atomic append serializes them,
  exactly one succeeds); and a duplicate dispatch after the Nebulex cache reservation has expired
  (proving the Reservation aggregate, not the cache, is the real ground truth — mirroring the
  prior design's identical DB-catches-what-cache-doesn't proof, just against the event store's own
  concurrency control instead of a DB unique index).

## Composability with `:cache`

Unchanged from the prior spec: `NewApiApp.Cache.Store` (the `:cache` plugin) and
`NewApiApp.CQRS.Cache` remain separate, independent Nebulex instances serving different purposes.
`:cqrs` still declares no `requires`/`conflicts` on `:cache`, and remains `derived_from: :api`.

## Out of scope

- `mix capstone.gen` / per-resource code generation (unchanged from the prior spec).
- Multi-node/distributed EventStore or Commanded dispatch beyond a single node — both the real
  EventStore adapter and Commanded's own registry/pubsub default to `:local` in this design; a
  project needing multi-node consistency upgrades these itself later.
- Automatic re-reservation when an update changes a previously-reserved unique field (documented
  developer responsibility, not silently unsupported — see Update Support above).
- Choosing an alternative EventStore storage/serialization backend beyond the Postgres +
  `Commanded.Serialization.JsonSerializer` default.
- Event versioning/upcasting strategies for evolving event schemas over an aggregate's lifetime —
  a real concern for any event-sourced system, but a per-project decision outside a starter
  plugin's scope; the README notes it as a forward-looking concern without prescribing one.

## Verification notes (empirical checks the implementation plan must re-confirm)

Everything in this spec was checked against real, current hexdocs (`commanded`, `eventstore`,
`uniq`, all fetched 2026-08-28) rather than assumed from general knowledge, matching the rigor the
prior spec applied to Nebulex 3.0's API. Two items are still worth an explicit re-check during
implementation, since the fetched docs summarized rather than quoted the source verbatim:
- `Commanded.EventStore.Adapters.InMemory.reset!/1`'s exact arity/argument (application module vs.
  otp_app atom) — confirm against the installed version's actual source before relying on it in
  the shipped tests' `setup` blocks.
- Whether `EventStore.Tasks.Init`/`Create` require any additional config (e.g., an
  `event_store.exs`-style file) beyond what's declared in `config/config.exs` — confirm during
  Task-equivalent-of-1's throwaway-copy compile/setup check, the same way the prior plan verified
  Nebulex's real dependency surface empirically rather than trusting the brief.
- `Commanded.Commands.Router`'s `dispatch/2` macro accepting a *list* of command modules sharing
  one `to:`/`identity:` clause (used above for `Reservation.Router`'s `[Reserve, Release]`) —
  the fetched docs only showed a single-command `dispatch` example; confirm the list form against
  the installed version's macro source, and fall back to two separate `dispatch` clauses (one per
  command, identical options) if it isn't supported.
