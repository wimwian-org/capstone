# `:grpc` plugin — server + client gRPC infrastructure — design

Date: 2026-08-28
Status: approved, pending implementation plan

## Purpose

A new capstone plugin, `derived_from: :api`, giving a generated project both a gRPC server
(exposing its own API over gRPC) and a gRPC client (calling other services over gRPC), with
TLS required by default rather than left as a documented follow-up. Built the same way every
other plugin is: a full project tree under `priv/meta/grpc_component/`, hand-authored by copying
and editing `priv/meta/baseline_api/`, diffed automatically by `mix capstone.plugin.derive grpc`
into `priv/meta/meta_grpc/manifest.exs`.

Per goals.md D17 / the plugin-ecosystem design's continuation notes, there is still no
`mix capstone.gen`. The plugin ships reusable library/infrastructure code only — no `.proto`
file, no generated service module, no example gRPC service compiled into the plugin tree — with
a complete worked example in the README instead, matching every existing plugin's convention
(most recently `:cqrs`'s).

## Dependencies

**Important — verified against the real, current Hex package structure, which has changed since
older Elixir gRPC tutorials were written:** the `elixir-grpc/grpc` project split into three
separate Hex packages at some point before this spec was written (checked 2026-08-28, current
versions 1.0.4 across all three):

- `grpc_core` — shared types, codecs, utilities. A required, transitive dependency of `grpc`
  (declared as `grpc_core ~> 1.0.4` in `grpc`'s own `mix.exs` requirements) — never add it
  directly.
- `grpc` (`{:grpc, "~> 1.0"}`) — the **client** implementation. Depends on `grpc_core`
  automatically; `castore`/`gun`/`mint` are its own optional transport-adapter dependencies,
  already resolved by `grpc` itself.
- `grpc_server` (`{:grpc_server, "~> 1.0"}`) — the **server** implementation. A genuinely
  separate package — must be added explicitly for server support. This plugin needs both since
  it provides server AND client infrastructure.

Full deps list added to `priv/meta/grpc_component/mix.exs`, appended after the existing deps:

```elixir
{:grpc, "~> 1.0"},
{:grpc_server, "~> 1.0"},
{:protobuf, "~> 0.13"},
{:x509, "~> 0.8", only: [:dev, :test], runtime: false}
```

`{:x509, ...}` is scoped `only: [:dev, :test], runtime: false` — it exists solely to generate
self-signed dev/test certificates and must never ship in a production release, exactly matching
how Phoenix itself scopes `x509` for its own `mix phx.gen.cert` task.

## Architecture overview

```
Generated project
   │
   ├── NewApiApp.GRPC.Endpoint (GRPC.Endpoint, ships with `run []` — developer
   │     extends with their own service modules, same shape as Phoenix's own
   │     generated router shipping with a minimal but real pipeline)
   │       │
   │       ▼
   │   {GRPC.Server.Supervisor, endpoint: ..., port: ..., start_server: true,
   │     adapter_opts: [cred: NewApiApp.GRPC.Credentials.server_credential()]}
   │       (one new application.ex supervision child)
   │
   └── NewApiApp.GRPC.Client — a small, stateless helper wrapping
         GRPC.Stub.connect/2 with the same TLS credential machinery,
         for calling OTHER services
             │
             ▼
         GRPC.Stub.connect(address, cred: NewApiApp.GRPC.Credentials.client_credential())

NewApiApp.GRPC.Credentials — shared cert/key-path → GRPC.Credential.new/1 builder,
used by both the server child spec and the client helper.

mix <app>.grpc.gen        — wraps `protoc`, generates .pb.ex from priv/protos/*.proto
mix <app>.grpc.gen.cert   — mirrors Phoenix's own `phx.gen.cert`; generates a
                            self-signed dev/test certificate via `x509`
```

What capstone ships as real code in `grpc_component/`:
- `NewApiApp.GRPC.Endpoint` — `use GRPC.Endpoint`, `run []` (empty, ready for a developer's own
  services — see Server below for why this differs from `:cqrs`'s "nothing shipped" precedent).
- `NewApiApp.GRPC.Credentials` — builds a `GRPC.Credential` struct from config-driven cert/key
  file paths, shared by both the server child spec and the client helper.
- `NewApiApp.GRPC.Client` — the client-side connect helper.
- `Mix.Tasks.<App>.Grpc.Gen` — the `protoc`-wrapping mix task.
- `Mix.Tasks.<App>.Grpc.Gen.Cert` — the cert-generation mix task.

What capstone does **not** ship (README worked example only): any `.proto` file, generated
`.pb.ex` service/message code, or an actual gRPC service module — these are inherently
domain-specific, the same reasoning `:cqrs` already established for why no fixture aggregate is
shipped.

## Server

### `NewApiApp.GRPC.Endpoint`

```elixir
defmodule NewApiApp.GRPC.Endpoint do
  use GRPC.Endpoint

  run []
end
```

Unlike `:cqrs`'s `Reservation.Router` (shipped fully "empty" of anything domain-specific because
it's genuinely generic infrastructure) or a fully doc-only Router (nothing shipped at all because
it's fully domain-specific), `GRPC.Endpoint`'s `run [...]` list sits in between: the ENDPOINT
MODULE itself is generic (any project needs exactly one), but its contents are 100% the
developer's own service modules. Shipping it with an empty `run []` mirrors Phoenix's own
generated `router.ex`, which ships with a real, working (if nearly empty) pipeline a developer
extends — not a documentation-only stub. This keeps `mix capstone.new --plugins :grpc` producing
a project whose gRPC server genuinely starts and serves (an empty service list, not an error),
consistent with every other plugin's "compiles and runs cleanly out of the box" bar.

### `NewApiApp.GRPC.Credentials`

```elixir
defmodule NewApiApp.GRPC.Credentials do
  @moduledoc """
  Builds the GRPC.Credential shared by the server's supervision child and
  NewApiApp.GRPC.Client — both sides of this plugin's gRPC infrastructure
  are TLS-required, no plaintext fallback.
  """

  @doc "Server-side credential: presents this app's own certificate."
  def server_credential do
    config = Application.fetch_env!(:new_api_app, __MODULE__)

    GRPC.Credential.new(
      ssl: [
        certfile: Keyword.fetch!(config, :certfile),
        keyfile: Keyword.fetch!(config, :keyfile)
      ]
    )
  end

  @doc "Client-side credential: trusts the given CA when calling another service."
  def client_credential do
    config = Application.fetch_env!(:new_api_app, __MODULE__)

    GRPC.Credential.new(ssl: [cacertfile: Keyword.fetch!(config, :cacertfile)])
  end
end
```

`GRPC.Credential.new/1` (verified against the real, current `elixir-grpc/grpc` source,
`grpc_core/lib/grpc/credential.ex`) validates only that `opts` is `[:ssl]`-shaped and stores
`%GRPC.Credential{ssl: opts[:ssl] || []}` — the `:ssl` keyword list is passed straight through
to Erlang's `:ssl` application, so `certfile`/`keyfile`/`cacertfile` are genuine `:ssl` option
keys, not this plugin's own invention.

### Wiring

`config/config.exs` (before `import_config`, same auto-detected `:before_import` mechanism every
other plugin relies on):

```elixir
config :new_api_app, NewApiApp.GRPC.Credentials,
  certfile: "priv/cert/selfsigned.pem",
  keyfile: "priv/cert/selfsigned_key.pem",
  cacertfile: "priv/cert/selfsigned.pem"

config :new_api_app, NewApiApp.GRPC.Endpoint, port: 50051
```

The paths above are the dev/test defaults (see `mix <app>.grpc.gen.cert` below) — `config/runtime.exs`
documents overriding all three via env vars for production, mirroring exactly how
`baseline_api/config/runtime.exs` already handles `NewApiApp.Repo`'s prod credentials (gated by
`if config_env() == :prod`).

`application.ex` gains ONE new supervision child (unlike `:cqrs`'s early mistake, this is
correctly a single addition from the start, so it hits the existing, proven single-child
auto-detection cleanly — no `:manual`/removal-hunk risk):

```elixir
{GRPC.Server.Supervisor,
 endpoint: NewApiApp.GRPC.Endpoint,
 port: Application.compile_env!(:new_api_app, [NewApiApp.GRPC.Endpoint, :port]),
 start_server: true,
 adapter_opts: [cred: NewApiApp.GRPC.Credentials.server_credential()]}
```

**Verified against real, current source, not assumed** (`grpc_server/lib/grpc/server/supervisor.ex`):
`GRPC.Server.Supervisor`'s accepted top-level options are exactly `:endpoint, :servers,
:start_server, :port, :adapter_opts, :exception_log_filter, :max_body_size` — there is **no
top-level `:cred` key**. The credential must be nested under `:adapter_opts` (confirmed by
`validate_cred/1`'s own implementation, which reads `Kernel.get_in(opts, [:adapter_opts,
:cred])`) — several older blog posts and tutorials show a bare `cred:` key, which is stale
relative to the current library version this plugin targets.

## Client

### `NewApiApp.GRPC.Client`

```elixir
defmodule NewApiApp.GRPC.Client do
  @moduledoc """
  Connects to another gRPC service, presenting this app's own client
  certificate machinery. Stateless — the caller holds and manages the
  returned channel's lifetime. No connection pooling in this version (see
  the design spec's Out of Scope section).
  """

  @spec connect(binary()) :: {:ok, GRPC.Channel.t()} | {:error, term()}
  def connect(address) do
    GRPC.Stub.connect(address, cred: NewApiApp.GRPC.Credentials.client_credential())
  end
end
```

`GRPC.Stub.connect/2`'s `cred:` option (verified against the real, current `grpc` client source)
is the correct, TOP-level key for the CLIENT side — this is deliberately different from the
SERVER side's nested `adapter_opts: [cred: ...]`, a real, confirmed asymmetry between the two
APIs, not a typo to "fix" into consistency.

A developer calling another service does:

```elixir
{:ok, channel} = NewApiApp.GRPC.Client.connect("other-service.internal:50051")
{:ok, reply} = channel |> OtherService.Stub.some_rpc(request)
```

## Codegen tooling: `mix <app>.grpc.gen`

```elixir
defmodule Mix.Tasks.NewApiApp.Grpc.Gen do
  @moduledoc """
  Compiles every .proto file under priv/protos/ into lib/new_api_app/grpc/generated/.

  Requires `protoc` and `protoc-gen-elixir` installed on PATH — this task
  wraps the invocation, it does not install the compiler toolchain itself
  (a system binary, not something Hex can provide).
  """
  use Mix.Task

  @proto_dir "priv/protos"
  @out_dir "lib/new_api_app/grpc/generated"

  @impl Mix.Task
  def run(_args) do
    File.mkdir_p!(@out_dir)

    protos = Path.wildcard(Path.join(@proto_dir, "*.proto"))

    if protos == [] do
      Mix.shell().info("No .proto files found under #{@proto_dir}/ — nothing to generate.")
    else
      args =
        ["--elixir_out=plugins=grpc:#{@out_dir}", "--proto_path=#{@proto_dir}"] ++ protos

      case System.cmd("protoc", args, stderr_to_stdout: true) do
        {output, 0} -> Mix.shell().info(output)
        {output, code} -> Mix.raise("protoc exited with status #{code}:\n#{output}")
      end
    end
  end
end
```

The exact `protoc`/`protoc-gen-elixir` flag set (`--elixir_out=plugins=grpc:...`) is drawn from
the `protobuf`/`grpc` ecosystem's own documented convention but was NOT independently verified
against a real `protoc-gen-elixir` invocation during spec-writing (unlike the deps/Credential/
Supervisor APIs above, which were) — **the implementation plan must verify this empirically**
(install `protoc`+`protoc-gen-elixir`, compile a trivial `.proto`, confirm the flags produce
valid, loadable `.pb.ex` output) before treating this code as final, the same rigor already
applied to every other verified claim in this spec.

## Cert tooling: `mix <app>.grpc.gen.cert`

Mirrors Phoenix's own `mix phx.gen.cert` almost exactly (same `x509` self-signed-CA-then-leaf
pattern), differing only in the file names/paths this plugin's config expects
(`priv/cert/selfsigned.pem` / `priv/cert/selfsigned_key.pem`, vs. Phoenix's own
`priv/cert/selfsigned_key.pem`/`selfsigned.pem` naming for HTTPS). **The exact `x509` API calls
(certificate/key generation, validity period, subject name) must be verified against Phoenix's
own real `phx.gen.cert` task source during implementation** — this spec intentionally does not
guess at the precise `X509.Certificate`/`X509.PrivateKey` call shapes without having read that
real source first, the same discipline already applied above for the deps/Credential/Supervisor
APIs.

## Testing

- **Shipped, real (not mocked) round-trip test**: unlike `:cqrs`'s shipped tests (which correctly
  do NOT call `start_supervised!` on anything `application.ex` already starts — a real bug was
  found and fixed the hard way when an earlier version of those tests tried to `start_supervised!`
  a process the app's own supervision tree had already started, crashing with
  `{:already_started, pid}`), this plugin's `GRPC.Server.Supervisor` is ALSO an unconditional
  `application.ex` child in every env, including `:test`. So the shipped test does **not** start
  anything itself — `mix test` already boots the full OTP application (with the server running,
  configured against a test cert generated by `mix <app>.grpc.gen.cert` and committed as a
  fixture — `priv/cert/selfsigned.pem`/`selfsigned_key.pem` checked into the plugin tree, matching
  how a real project commits its own dev/test certs, NOT regenerated fresh per test run) before
  any test body runs. The test simply calls `NewApiApp.GRPC.Client.connect/1` against the
  already-running server for a genuine client↔server TLS round trip — no `start_supervised!`
  anywhere. Since no actual `.proto`-defined service is shipped (per the "infrastructure only"
  scope), this test exercises connection/TLS-handshake success against the empty
  `NewApiApp.GRPC.Endpoint` — not a real RPC call (there's no service to call) — proving the
  supervision, credential, and TLS wiring are correct, which is everything capstone itself is
  responsible for.
- **Capstone's own toolchain test** (mirroring `:cache`'s and `:cqrs`'s own structural toolchain
  tests): a real `mix capstone.new --plugins :grpc` + `mix compile` + a smoke check that
  `Application.ensure_all_started/1` succeeds (proving `GRPC.Server.Supervisor` actually starts
  under real config, not just that files landed) — run via `mix test` (not `mix run -e`), per the
  `:cqrs` plan's own hard-won lesson about `Shell.cmd!/3` never reliably reaching a specific
  non-default `MIX_ENV`.

## Composability

`:grpc` is independent of every other plugin — no `requires`/`conflicts` on `:cache` or `:cqrs`.
Its own supervision child, config namespace (`NewApiApp.GRPC.*`), and deps are self-contained.

## Out of scope

- Any actual `.proto` service definition or generated service/message code (README worked
  example only — same reasoning as every other plugin's fixture-free convention).
- Client-side connection pooling — `NewApiApp.GRPC.Client.connect/1` is a stateless, one-shot
  helper for v1; a project needing a pooled/supervised channel manager builds one itself later,
  documented as a forward-looking extension in the README, not prescribed here.
- gRPC reflection and health-checking services (`grpc_reflection`/standard health-check protocol)
  — real, common production additions, but a separate concern from this plugin's core
  server+client+TLS infrastructure scope.
- Streaming RPC worked examples — the README's worked example covers a basic unary call only;
  streaming (client-streaming, server-streaming, bidirectional) is real `grpc`/`protobuf`
  functionality the plugin doesn't need to demonstrate to prove its own infrastructure works.
- mTLS (mutual TLS, verifying the CLIENT's certificate on the server side) — this spec's
  `GRPC.Credential` usage is one-directional (server presents a cert, client trusts a CA); a
  project needing mutual authentication extends `NewApiApp.GRPC.Credentials.server_credential/0`
  itself (documented as a follow-up in the README), not shipped as a default here.

## Verification notes (empirical checks the implementation plan must re-confirm)

Everything in the Dependencies, Server, and Client sections above was checked against real,
current Hex/GitHub source (`elixir-grpc/grpc`'s `grpc`/`grpc_core`/`grpc_server` packages, version
1.0.4, fetched 2026-08-28) — the same rigor the `:cqrs` spec applied to Nebulex/Commanded/
EventStore. Two items were explicitly NOT verified this way and are flagged inline above for the
implementation plan to confirm empirically before finalizing:
- The `mix <app>.grpc.gen` task's exact `protoc`/`protoc-gen-elixir` flag set.
- The `mix <app>.grpc.gen.cert` task's exact `x509` API calls (best verified by reading Phoenix's
  own real `phx.gen.cert` task source directly, since it's the explicit precedent this task
  mirrors).
