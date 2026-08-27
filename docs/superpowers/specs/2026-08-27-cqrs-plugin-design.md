# CQRS plugin, and a real :cache — design

Date: 2026-08-27
Status: approved, pending implementation plan

## Purpose

Two plugin changes, delivered together because the second depends on the
first not existing to lean on:

1. **Fix `:cache`.** The plugin declares `{:nebulex, "~> 3.0"}` as a
   dependency but never uses it — `lib/APP/cache.ex` is a bare
   `:persistent_term` read-through cache with no expiry and nothing
   supervised. Any project applying `:cache` today ships a dead dependency.
2. **Add `:cqrs`.** A new plugin, `derived_from: :api` (not `:cache` — a
   project must be able to apply `:cqrs` without `:cache`), giving a
   generated project a Command/Query/Dispatcher shape with UUIDv7 primary
   keys and a uniqueness-check pipeline: a short-term cache reservation
   (fast reject, guards the race between check and write) backed by real DB
   unique constraints (ground truth).

Both are built the same way `:cache`/`:openapi`/`:prod_image_api` already
are: a full project tree under `priv/meta/<name>_component/`, hand-written
by copying and editing `priv/meta/baseline_api`, diffed automatically by
`mix capstone.plugin.derive` into `priv/meta/meta_<name>/manifest.exs`. No
new plugin-authoring tooling — this spec is entirely about what those two
component trees contain.

Per goals.md D17 / the plugin-ecosystem design's continuation notes, there is
still no `mix capstone.gen`. Neither plugin here generates a resource; both
ship reusable library modules a developer writes their own schemas and
commands against by hand.

## `:cache` fix

### Current shape (being replaced)

```elixir
defmodule <App>.Cache do
  def fetch(key, fun) when is_function(fun, 0) do
    case :persistent_term.get({__MODULE__, key}, :miss) do
      :miss -> value = fun.(); :persistent_term.put({__MODULE__, key}, value); value
      value -> value
    end
  end
end
```

### New shape

`lib/APP/cache/store.ex` — the real cache, a `Nebulex.Cache` instance:

```elixir
defmodule <App>.Cache.Store do
  use Nebulex.Cache, otp_app: :<app>, adapter: Nebulex.Adapters.Local
end
```

`lib/APP/cache.ex` — same public shape as today, `fetch/2`, plus a new
`fetch/3` for TTL, both delegating to `Store`:

```elixir
defmodule <App>.Cache do
  alias <App>.Cache.Store

  @miss :__cache_miss__

  @doc "Fetches `key`, computing it with `fun` on a miss. Never expires."
  def fetch(key, fun) when is_function(fun, 0), do: fetch(key, :infinity, fun)

  @doc "Fetches `key`, computing it with `fun` on a miss. Expires after `ttl` ms."
  def fetch(key, ttl, fun) when is_function(fun, 0) do
    case Store.get(key, @miss, []) do
      {:ok, @miss} ->
        value = fun.()
        :ok = Store.put(key, value, ttl: ttl)
        value

      {:ok, value} ->
        value
    end
  end
end
```

`ttl: :infinity` is Nebulex's own no-expiry value — `fetch/2`'s behavior is
unchanged from today's caller's point of view (compute-on-miss, cached
forever), only the backend moves from `:persistent_term` to a real,
supervised cache. `get/3` (key, default, opts) and `put/3` (key, value,
opts) are Nebulex 3.0's real signatures — both return-wrapped
(`get/3` → `{:ok, value}`; `put/3` → `:ok | {:error, reason}`), verified
against `Nebulex.Cache`'s 3.0.4 documentation. A local, private sentinel
atom (`@miss`) distinguishes "no entry" from a legitimately cached `nil`,
since `get/3`'s own default-value parameter would conflate the two.

### Wiring

- `config/config.exs` gains a `config :<app>, <App>.Cache.Store, ...`
  block — auto-captured by `Derive`'s existing `:before_import`/`{:env,
  env}` placement detection, same mechanism every other config-touching
  plugin already relies on. No explicit adapter options needed beyond the
  local adapter default.
- `lib/APP/application.ex` gains `<App>.Cache.Store` as a supervision
  child — auto-detected by `Derive`'s `added_child/2` diff against baseline
  (see `Capstone.Plugin.Apply.add_supervision_child/4` and
  `Capstone.Source.ApplicationEx`), the same mechanism the plugin-ecosystem
  design doc calls out as "the most common structural edit a plugin makes"
  but which `:cache` never actually exercised until now.

No change to `deps` (nebulex is already declared) or to the README
contribution's wording beyond removing any claim of no-expiry-only behavior.

## `:cqrs` plugin

### Modules

All under `lib/APP/cqrs/`, all `:sole_owner`.

**`command.ex`** — behaviour:

```elixir
defmodule <App>.CQRS.Command do
  @callback changeset(params :: map()) :: Ecto.Changeset.t()
  @callback unique_fields() :: [[atom()]]
end
```

A command module wraps one Ecto schema. `unique_fields/0` returns a list of
field groups; each inner list is one composite uniqueness constraint, e.g.
`[[:email], [:org_id, :username]]` means "email alone must be unique, and
the (org_id, username) pair must be unique." Every inner list must be
non-empty — `UniqueCheck` calls `hd(group)` to attach the "has already been
taken" error to the group's first field.

**`query.ex`** — behaviour:

```elixir
defmodule <App>.CQRS.Query do
  @callback run(params :: map()) :: {:ok, term()} | {:error, term()}
end
```

No caching, no uniqueness — reads are a direct pass-through. `Dispatcher`
exists on the read side purely so callers have one entry point for both
commands and queries; it adds no behavior of its own to `run/1`.

**`cache.ex`** — a dedicated `Nebulex.Cache` instance, independent of the
`:cache` plugin's (a project may apply `:cqrs` without `:cache`, and the two
caches serve different purposes — general-purpose vs. reservation-only):

```elixir
defmodule <App>.CQRS.Cache do
  use Nebulex.Cache, otp_app: :<app>, adapter: Nebulex.Adapters.Local
end
```

**`unique_check.ex`** — the reservation and DB-constraint logic:

```elixir
defmodule <App>.CQRS.UniqueCheck do
  alias <App>.CQRS.Cache

  @ttl :timer.seconds(30)

  @doc """
  Reserves every field group's cache key for `changeset`'s current values.
  Returns `{:ok, changeset, reserved_keys}` if every group was free, or
  `{:error, changeset}` (with a "has already been taken" error on the first
  field of the taken group) if any group was already reserved — releasing
  whatever this attempt had already reserved before returning.
  """
  def reserve(changeset, unique_fields) do
    schema = changeset.data.__struct__

    Enum.reduce_while(unique_fields, {:ok, changeset, []}, fn group, {:ok, cs, reserved} ->
      key = cache_key(schema, group, cs)

      case Cache.put_new(key, true, ttl: @ttl) do
        {:ok, true} ->
          {:cont, {:ok, cs, [key | reserved]}}

        {:ok, false} ->
          Enum.each(reserved, &Cache.delete(&1, []))
          {:halt, {:error, Ecto.Changeset.add_error(cs, hd(group), "has already been taken")}}
      end
    end)
  end

  @doc "Releases every field group's reservation for `changeset`. Called after a lost race."
  def release(changeset, unique_fields) do
    schema = changeset.data.__struct__
    Enum.each(unique_fields, &Cache.delete(cache_key(schema, &1, changeset), []))
    changeset
  end

  @doc """
  Adds `Ecto.Changeset.unique_constraint/3` for every group, named to match
  the default name Ecto's own `unique_index/2` migration helper produces for
  that same field list — call this from inside a command's `changeset/2`.
  The matching migration needs no explicit `:name` option; just declare the
  index over the same fields, in the same order, as the group.
  """
  def validate_unique_constraints(changeset, unique_fields) do
    source = changeset.data.__struct__.__schema__(:source)

    Enum.reduce(unique_fields, changeset, fn group, cs ->
      name = :"#{source}_#{Enum.join(group, "_")}_index"
      Ecto.Changeset.unique_constraint(cs, hd(group), name: name, fields: group)
    end)
  end

  defp cache_key(schema, group, changeset) do
    {schema, group, Enum.map(group, &Ecto.Changeset.get_field(changeset, &1))}
  end
end
```

`reserve/2` reserving nothing when `unique_fields/0` returns `[]` is fine —
`Enum.reduce_while` over an empty list returns the initial accumulator,
`{:ok, changeset, []}`.

**`dispatcher.ex`**:

```elixir
defmodule <App>.CQRS.Dispatcher do
  alias <App>.CQRS.UniqueCheck
  alias <App>.Repo

  def dispatch(command_module, params) do
    changeset = command_module.changeset(params)

    if changeset.valid? do
      commit(command_module, changeset)
    else
      {:error, changeset}
    end
  end

  def query(query_module, params), do: query_module.run(params)

  defp commit(command_module, changeset) do
    unique_fields = command_module.unique_fields()

    case UniqueCheck.reserve(changeset, unique_fields) do
      {:ok, changeset, _reserved} ->
        case Repo.insert(changeset) do
          {:ok, struct} ->
            {:ok, struct}

          {:error, changeset} ->
            UniqueCheck.release(changeset, unique_fields)
            {:error, changeset}
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
```

A successful insert leaves its reservations in place until the TTL expires
naturally — by then the DB row exists, so a subsequent uniqueness check on
the same values fails at the DB regardless of cache state. This is
deliberately not "insert, then immediately release": the TTL window also
covers replication lag on the DB side.

Updates that touch a unique field are out of scope for v1 — `dispatch/2`
only supports the create path (`Repo.insert/1`). Documented as a known
limitation in the README contribution, not silently unsupported.

### UUIDv7

Documented convention (no code generated — capstone doesn't know a
consuming project's schemas): a schema declares

```elixir
@primary_key {:id, Uniq.UUID, autogenerate: true, version: 7, type: :binary_id}
```

`{:uniq, "~> 0.6"}` is added to `deps`. `Uniq.UUID` implements
`Ecto.ParameterizedType`, not plain `Ecto.Type`, and defaults to `version:
4` — the explicit `version: 7` is required, not decorative. `type:
:binary_id` aligns the underlying dumped type with Postgres's native `uuid`
column and Phoenix's standard `--binary-id` migration convention (`add :id,
:binary_id, primary_key: true`); without it the default `dump: :raw`
resolves to bare `:binary`.

### Wiring

- `config/config.exs` — `config :<app>, <App>.CQRS.Cache, ...`, same
  auto-detected placement as the `:cache` fix above.
- `lib/APP/application.ex` — `<App>.CQRS.Cache` as a supervision child, same
  auto-detected mechanism.
- `README.md` contribution — documents the UUIDv7 primary-key convention,
  the unique-index-naming convention `validate_unique_constraints/2`
  depends on, and the create-only limitation.
- `deps` — `{:nebulex, "~> 3.0"}`, `{:uniq, "~> 0.6"}`.

### Composing with `:cache`

`:cqrs` and `:cache` (fixed) can both be applied to the same project — they
touch `config/config.exs` and `application.ex` at different, independently
merged `:contributes`/auto-detected-child slots (the same composition
`Capstone.Plugin.Apply` already relies on for any two plugins layered onto
one target), and their Nebulex instances (`<App>.Cache.Store` vs.
`<App>.CQRS.Cache`) are separate named caches with no shared state. Neither
plugin lists the other in `requires`/`conflicts`.

## Testing

Plugin-authoring rigor matches `:cache`/`:openapi`/`:prod_image_api` today:

- A round-trip test per plugin (derive from the component tree, re-apply
  onto a fresh `baseline_api` copy, assert byte-identical) — same shape as
  the existing tests in `test/capstone/plugin/round_trip_test.exs`.
- `mix compile` of the derived project as part of authoring verification.

`Command`/`Query`/`Dispatcher`/`UniqueCheck` additionally get real
behavioral tests shipped *inside* `cqrs_component/test/cqrs/` — baseline's
`test/` tree is already part of what every plugin ships, so these tests
become both capstone's own verification during authoring and living
regression coverage inside every project that applies `:cqrs`. Nebulex's
local adapter needs no external service; the `Repo.insert` path in
`dispatcher_test.exs` needs `Ecto.Adapters.SQL.Sandbox` against a real
Postgres, same as any Ecto app's own tests, and same as `baseline_api`
already assumes for its own generated `test/support/data_case.ex`. A local
Postgres is available in this environment, so these tests are written to
actually run (`mix ecto.create && mix ecto.migrate && mix test` inside
`cqrs_component` during authoring), not merely compiled.

Migration files that create the matching unique indexes are hand-written as
part of `cqrs_component`'s own fixture schema (used only for these tests,
never shipped — schemas are what a consuming project supplies, not the
plugin) to exercise `validate_unique_constraints/2` end-to-end, including
the DB-constraint-violation → cache-release path (two concurrent inserts,
one delayed past the cache TTL boundary, to prove the DB catches what the
cache's TTL expiry lets through).

## Out of scope

- Update commands that touch a unique field (v1 dispatch is create-only).
- `mix capstone.gen` / per-resource code generation — both plugins ship
  library modules only, per the existing continuation notes in
  `Mix.Tasks.Capstone.New`'s moduledoc.
- Distributed/multi-node cache adapters — both Nebulex instances use
  `Nebulex.Adapters.Local`; a project needing a distributed reservation
  cache (multiple app nodes) upgrades the adapter itself later.
- Fixing `:cache`'s dead dependency was scoped in explicitly during
  brainstorming (not part of the original ask) — no other existing plugin
  is touched by this spec.
