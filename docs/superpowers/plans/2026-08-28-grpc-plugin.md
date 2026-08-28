# gRPC Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a new `:grpc` capstone plugin giving a generated project both a gRPC server and a gRPC client, TLS required by default, with `protoc`-wrapping and self-signed-cert-generation mix tasks.

**Architecture:** `NewApiApp.GRPC.Endpoint` (server, ships empty `run []`) + `NewApiApp.GRPC.Credentials` (shared cert-path → `GRPC.Credential` builder) + `NewApiApp.GRPC.Client` (stateless connect helper) — one new `application.ex` supervision child (`GRPC.Server.Supervisor`). Two mix tasks: `mix <app>.grpc.gen` (wraps `protoc`) and `mix <app>.grpc.gen.cert` (self-signed cert generation, copied from Phoenix's own real `phx.gen.cert`, no extra dependency).

**Tech Stack:** Elixir 1.20, Phoenix 1.8, `grpc` 1.0 (client), `grpc_server` 1.0 (server), `grpc_core` 1.0 (transitive), `protobuf` 0.13.

**Spec:** `docs/superpowers/specs/2026-08-28-grpc-plugin-design.md`

## Global Constraints

- The plugin is built via the existing pipeline: hand-edit `priv/meta/grpc_component/`, then `mix capstone.plugin.derive grpc` diffs it against `priv/meta/baseline_api/` into `priv/meta/meta_grpc/manifest.exs`. Never hand-edit files under `priv/meta/meta_grpc/` directly.
- Deps: `{:grpc, "~> 1.0"}`, `{:grpc_server, "~> 1.0"}`, `{:protobuf, "~> 0.13"}`, `{:mint, "~> 1.9"}` — no `x509`, no `:gun`. `grpc_core` is a transitive dependency of `grpc`; never add it directly. `:mint` is an EXPLICIT dependency, not left to an accidental transitive pull-in: `grpc`'s default client adapter (`GRPC.Client.Adapters.Gun`) needs `:gun`, which this plugin doesn't install — `NewApiApp.GRPC.Client` explicitly selects `GRPC.Client.Adapters.Mint` instead (see Task 3), so `:mint` must be a real, declared dependency, confirmed against `grpc`'s own real hex requirements (`mint ~> 1.9`, an optional peer dep grpc expects the consumer to add if they want this adapter).
- `NewApiApp.GRPC.Credentials.client_credential/0` MUST include a `verify_fun` that accepts ONLY `{:bad_cert, :selfsigned_peer}` and fails every other bad-cert reason — OTP's `:ssl`/`:public_key` classifies ANY single self-signed certificate as `{bad_cert, :selfsigned_peer}` (confirmed against real OTP 29 `ssl_certificate.erl` source; long-standing, documented behavior, not version-specific), and `:verify_peer` treats this as fatal by default. Without this, the shipped test (and any real client, including a developer's own) can never successfully connect to this plugin's self-signed dev/test cert. This is a narrow, dev-cert-specific exception — never blanket-accept all bad-cert reasons, which would defeat the point of using TLS.
- `GRPC.Server.Supervisor`'s TLS credential goes under `adapter_opts: [cred: ...]` — NOT a bare top-level `cred:` key (verified against real, current `grpc_server` source; several older tutorials show the stale bare-key form). `GRPC.Stub.connect/2`'s credential (client side) IS a top-level `cred:` key — this asymmetry between server and client is real and confirmed, not a bug to "fix" into consistency.
- `application.ex` adds exactly ONE supervision child (`GRPC.Server.Supervisor`) — this should hit the existing single-child auto-detection (`Derive.added_child/2`, extended to N children by earlier, unrelated work on this branch) cleanly, landing as `:contributes`+`child:`, never `:manual`. Verify this in Task 7, don't assume it.
- The shipped test does **not** call `start_supervised!` on `GRPC.Server.Supervisor` or anything else `application.ex` already starts unconditionally in every env including `:test` — a real bug of exactly this shape was found and fixed the hard way in a separate, earlier plan on this branch (`:cqrs`'s Task 9). `mix test` already boots the full OTP application (server running) before any test body executes; the shipped test just calls `NewApiApp.GRPC.Client.connect/1` against the already-running server.
- Any `--include toolchain` test that applies `:grpc` via `Bootstrap.run/2` needs this branch's established local-packaging workaround if `:grpc` isn't published yet by the time these tasks run: `mix capstone.plugin.package grpc`, copy the resulting `priv/plugins/grpc-*.tar.gz` into `~/Library/Caches/capstone/plugins/`, removing any other `grpc-*.tar.gz` already there (a same-version/lexicographic-sha tiebreak bug was found on this branch — always keep only the freshly-packaged archive).
- A toolchain test's final `Application.ensure_all_started/1`-style smoke check must run via `Shell.cmd!(["test"], project)` (or a temp test file run through `mix test`), never `Shell.cmd!(["run", "-e", "..."], project)` — `Shell.cmd!/3` scrubs `MIX_ENV` for every child invocation and cannot be told to use a specific non-default env; only `mix test`'s own `preferred_cli_env` reliably reaches `:test`. This was a real, hard-won lesson from `:cqrs`'s Task 9 on this branch — do not repeat the `mix run -e` mistake.
- The `mix <app>.grpc.gen.cert` task's certificate/key generation code must be copied verbatim (renaming only the module and default path) from Phoenix's real, current `mix phx.gen.cert` implementation (`phoenixframework/phoenix`, `lib/mix/tasks/phx.gen.cert.ex`) — do not hand-retype the `:public_key` record definitions, OID constants, or ASN.1 structure from memory; fetch the real source and copy it.
- The `mix <app>.grpc.gen` task's exact `protoc`/`protoc-gen-elixir` invocation flags were NOT verified against a real `protoc-gen-elixir` run during spec-writing — Task 5 must install the toolchain and verify empirically, adjusting the flags if reality differs from the spec's draft.
- Default cert paths are `priv/cert/grpc_selfsigned.pem` / `priv/cert/grpc_selfsigned_key.pem` — deliberately different from Phoenix's own `priv/cert/selfsigned.pem`/`selfsigned_key.pem`, to avoid collision if a project ever uses both `:grpc` and Phoenix's own HTTPS `phx.gen.cert`.
- No fixture `.proto` file, generated service module, or example gRPC service is ever added to `priv/meta/grpc_component/` — the README's worked example is documentation only. The shipped test proves connection/TLS-handshake success against the empty `NewApiApp.GRPC.Endpoint`, not a real RPC call (there's no service to call).

---

## File Structure

**`:grpc` plugin** (all under `priv/meta/grpc_component/`, hand-edited; `priv/meta/meta_grpc/` regenerated by `derive`):
- Modify `mix.exs` — add the three deps.
- Create `lib/new_api_app/grpc/credentials.ex`.
- Create `lib/new_api_app/grpc/endpoint.ex`.
- Create `lib/new_api_app/grpc/client.ex`.
- Create `lib/mix/tasks/new_api_app.grpc.gen.cert.ex`.
- Create `lib/mix/tasks/new_api_app.grpc.gen.ex`.
- Create `priv/cert/grpc_selfsigned.pem`, `priv/cert/grpc_selfsigned_key.pem` (generated once via the cert mix task, then committed as shipped test/dev fixtures).
- Create `test/grpc/client_test.exs`.
- Modify `lib/new_api_app/application.ex` — append one supervision child.
- Modify `config/config.exs` — Credentials + Endpoint config before `import_config`.
- Modify `README.md` — worked example + `protoc`/cert setup steps.

**Capstone's own repo:**
- Modify `priv/baselines.exs` — new minimal `:grpc` entry, recomputed by `mix capstone.baseline.record` (Task 7).
- Create `test/capstone/plugin/grpc_round_trip_test.exs`.
- Modify `test/integration/plugin_lifecycle_test.exs` — new `:grpc` structural toolchain test.

---

### Task 1: Scaffold `priv/meta/grpc_component/` and `NewApiApp.GRPC.Credentials`

**Files:**
- Create: `priv/meta/grpc_component/` (full copy of `priv/meta/baseline_api/`)
- Modify: `priv/meta/grpc_component/mix.exs`
- Create: `priv/meta/grpc_component/lib/new_api_app/grpc/credentials.ex`
- Modify: `priv/meta/grpc_component/config/config.exs`
- Modify: `priv/baselines.exs`

**Interfaces:**
- Produces: a raw project tree with `grpc`/`grpc_server`/`protobuf` declared as deps, and `NewApiApp.GRPC.Credentials` — consumed by Tasks 2-3.

- [ ] **Step 1: Copy the baseline**

```bash
cp -r priv/meta/baseline_api priv/meta/grpc_component
```

- [ ] **Step 2: Add the four new deps to `mix.exs`**

Find the existing `deps/0` list (ends with `{:bandit, "~> 1.5"}`). Append:

```elixir
      {:bandit, "~> 1.5"},
      {:grpc, "~> 1.0"},
      {:grpc_server, "~> 1.0"},
      {:protobuf, "~> 0.13"},
      {:mint, "~> 1.9"}
```

`{:mint, "~> 1.9"}` is required EXPLICITLY (not left to an accidental transitive pull-in from an
unrelated dep): `grpc`'s default client adapter (`GRPC.Client.Adapters.Gun`) needs the `:gun`
package, which this plugin doesn't install; `NewApiApp.GRPC.Client` (Task 3) explicitly selects
`GRPC.Client.Adapters.Mint` instead, so `:mint` must be a real, declared dependency — confirmed
against `grpc`'s own real hex requirements (`mint ~> 1.9`, one of its two optional adapter peer
deps, the other being `gun`).

- [ ] **Step 3: Create `lib/new_api_app/grpc/credentials.ex`**

```elixir
defmodule NewApiApp.GRPC.Credentials do
  @moduledoc """
  Builds the GRPC.Credential shared by the server's supervision child and
  NewApiApp.GRPC.Client — both sides of this plugin's gRPC infrastructure
  are TLS-required, no plaintext fallback.
  """

  @doc "Server-side credential: presents this app's own certificate."
  @spec server_credential() :: GRPC.Credential.t()
  def server_credential do
    config = Application.fetch_env!(:new_api_app, __MODULE__)

    GRPC.Credential.new(
      ssl: [
        certfile: Keyword.fetch!(config, :certfile),
        keyfile: Keyword.fetch!(config, :keyfile)
      ]
    )
  end

  @doc """
  Client-side credential: trusts the given CA when calling another service.

  Includes a verify_fun accepting ONLY the {:bad_cert, :selfsigned_peer}
  reason — OTP's :ssl/:public_key classifies ANY single self-signed
  certificate presented by a peer this way (confirmed against real OTP 29
  ssl_certificate.erl source; long-standing, documented :public_key
  behavior, not version-specific), and :verify_peer treats it as fatal by
  default. Without this, no client — including this plugin's own shipped
  test — can ever connect to the self-signed dev/test cert this plugin
  ships. Every OTHER bad-cert reason still fails: this is a narrow,
  dev-cert-specific exception, never a blanket bypass.
  """
  @spec client_credential() :: GRPC.Credential.t()
  def client_credential do
    config = Application.fetch_env!(:new_api_app, __MODULE__)

    GRPC.Credential.new(
      ssl: [
        cacertfile: Keyword.fetch!(config, :cacertfile),
        verify_fun:
          {fn
             _, {:bad_cert, :selfsigned_peer}, state -> {:valid, state}
             _, {:bad_cert, _} = reason, _ -> {:fail, reason}
             _, {:extension, _}, state -> {:unknown, state}
             _, :valid, state -> {:valid, state}
             _, :valid_peer, state -> {:valid, state}
           end, []}
      ]
    )
  end
end
```

If `GRPC.Credential.t()` isn't a defined type in the installed `grpc_core` version (it may not
export a `@type t`), drop the `@spec` return type annotation rather than referencing a
nonexistent type — check `mix docs`/the installed package source if `mix compile` warns about it.

- [ ] **Step 4: Add the config block to `config/config.exs`**

Insert immediately before the trailing `import_config` line:

```elixir
# Configure gRPC TLS credentials (server and client share these)
config :new_api_app, NewApiApp.GRPC.Credentials,
  certfile: "priv/cert/grpc_selfsigned.pem",
  keyfile: "priv/cert/grpc_selfsigned_key.pem",
  cacertfile: "priv/cert/grpc_selfsigned.pem"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
```

- [ ] **Step 5: Add the minimal `:grpc` entry to `priv/baselines.exs`**

Insert a new `grpc:` key (after whichever existing entry sorts alphabetically before it):

```elixir
  grpc: %{
    derived_from: :api,
    names: %{app: "new_api_app", module: "NewApiApp", name: "new_api_app"},
    path: "priv/meta/grpc_component"
  },
```

This is intentionally minimal — `mix capstone.baseline.record` (Task 7) recomputes
`files:`/`tree_digest:`/`archive_sha256:` and rewrites the whole file.

- [ ] **Step 6: Verify it compiles**

```bash
cd priv/meta/grpc_component
mix deps.get
mix compile --warnings-as-errors
cd -
```

If `mix deps.get` fails to resolve `grpc`/`grpc_server`/`protobuf`, treat it as a real problem to
diagnose (version conflict, hex availability), not something to route around.

- [ ] **Step 7: Verify `priv/baselines.exs` still parses**

```bash
mix run -e 'IO.inspect(Capstone.Baseline.read!("priv/baselines.exs") |> Map.keys())'
```

Expected: includes `:grpc`.

- [ ] **Step 8: Commit**

```bash
git add priv/meta/grpc_component priv/baselines.exs
git commit -m "feat(plugin): scaffold priv/meta/grpc_component with NewApiApp.GRPC.Credentials"
```

---

### Task 2: `NewApiApp.GRPC.Endpoint` and application.ex wiring

**Files:**
- Create: `priv/meta/grpc_component/lib/new_api_app/grpc/endpoint.ex`
- Modify: `priv/meta/grpc_component/lib/new_api_app/application.ex`
- Modify: `priv/meta/grpc_component/config/config.exs`

**Interfaces:**
- Consumes: `NewApiApp.GRPC.Credentials.server_credential/0` (Task 1).
- Produces: `NewApiApp.GRPC.Endpoint`, a running (if empty) gRPC server — consumed by Task 6's shipped test.

- [ ] **Step 1: Create `lib/new_api_app/grpc/endpoint.ex`**

```elixir
defmodule NewApiApp.GRPC.Endpoint do
  @moduledoc """
  This project's gRPC server endpoint. Ships empty — add your own service
  modules to the `run` list below (see the README's worked example).
  """

  use GRPC.Endpoint

  run []
end
```

- [ ] **Step 2: Extend the config block in `config/config.exs`**

Extend the SAME contiguous pre-`import_config` block Task 1 started (insert right after the
Credentials config, still before `import_config`):

```elixir
# Configure gRPC TLS credentials (server and client share these)
config :new_api_app, NewApiApp.GRPC.Credentials,
  certfile: "priv/cert/grpc_selfsigned.pem",
  keyfile: "priv/cert/grpc_selfsigned_key.pem",
  cacertfile: "priv/cert/grpc_selfsigned.pem"

# Configure the gRPC server's port
config :new_api_app, NewApiApp.GRPC.Endpoint, port: 50051

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
```

- [ ] **Step 3: Append the supervision child to `application.ex`**

Change ONLY the `children` list (nothing else in the file), appending as the literal last
element:

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
      {GRPC.Server.Supervisor,
       endpoint: NewApiApp.GRPC.Endpoint,
       port: Application.fetch_env!(:new_api_app, NewApiApp.GRPC.Endpoint)[:port],
       start_server: true,
       adapter_opts: [cred: NewApiApp.GRPC.Credentials.server_credential()]}
    ]
```

This is exactly ONE new list element (a 4-key tuple), matching the same shape as the
already-proven single-child auto-detection.

- [ ] **Step 4: Verify it compiles**

```bash
cd priv/meta/grpc_component
mix compile --warnings-as-errors
cd -
```

Expected: compiles cleanly. The server won't actually start correctly yet since the cert files
referenced by config don't exist on disk until Task 4 generates them — if `mix compile` itself
fails (not just a runtime start failure) for an unrelated reason, investigate before continuing.

- [ ] **Step 5: Commit**

```bash
git add priv/meta/grpc_component/lib/new_api_app/grpc/endpoint.ex \
        priv/meta/grpc_component/lib/new_api_app/application.ex \
        priv/meta/grpc_component/config/config.exs
git commit -m "feat(plugin): add NewApiApp.GRPC.Endpoint and wire the server into application.ex"
```

---

### Task 3: `NewApiApp.GRPC.Client`

**Files:**
- Create: `priv/meta/grpc_component/lib/new_api_app/grpc/client.ex`

**Interfaces:**
- Consumes: `NewApiApp.GRPC.Credentials.client_credential/0` (Task 1).
- Produces: `NewApiApp.GRPC.Client.connect/1` — consumed by Task 6's shipped test and the README's worked example.

- [ ] **Step 1: Create `lib/new_api_app/grpc/client.ex`**

```elixir
defmodule NewApiApp.GRPC.Client do
  @moduledoc """
  Connects to another gRPC service, presenting this app's own client
  certificate machinery. Stateless — the caller holds and manages the
  returned channel's lifetime. No connection pooling in this version; a
  project needing a pooled/supervised channel manager builds one itself.
  """

  @doc "Connects to `address` (e.g. \"other-service.internal:50051\")."
  @spec connect(binary()) :: {:ok, GRPC.Channel.t()} | {:error, term()}
  def connect(address) do
    GRPC.Stub.connect(address,
      cred: NewApiApp.GRPC.Credentials.client_credential(),
      adapter: GRPC.Client.Adapters.Mint
    )
  end
end
```

`adapter: GRPC.Client.Adapters.Mint` is required explicitly — `grpc`'s own default
(`GRPC.Client.Adapters.Gun`) needs the `:gun` package, which this plugin doesn't install (see
Task 1's `:mint` dependency note).

- [ ] **Step 2: Verify it compiles**

```bash
cd priv/meta/grpc_component
mix compile --warnings-as-errors
cd -
```

- [ ] **Step 3: Commit**

```bash
git add priv/meta/grpc_component/lib/new_api_app/grpc/client.ex
git commit -m "feat(plugin): add NewApiApp.GRPC.Client"
```

---

### Task 4: `mix <app>.grpc.gen.cert` and the shipped test/dev certificate fixture

**Files:**
- Create: `priv/meta/grpc_component/lib/mix/tasks/new_api_app.grpc.gen.cert.ex`
- Create: `priv/meta/grpc_component/priv/cert/grpc_selfsigned.pem`, `grpc_selfsigned_key.pem`

**Interfaces:**
- Produces: `mix new_api_app.grpc.gen.cert` (documented in the README, Task 6) and a committed
  test/dev cert pair — consumed by Task 6's shipped test and Task 9's toolchain test.

- [ ] **Step 1: Create `lib/mix/tasks/new_api_app.grpc.gen.cert.ex`**

This is adapted directly from Phoenix's own real, current `mix phx.gen.cert`
(`phoenixframework/phoenix`, `lib/mix/tasks/phx.gen.cert.ex`, fetched and verified 2026-08-28) —
the certificate/key-generation logic (the `Record.defrecordp` calls, OID constants,
`certificate_and_key/3`, `new_cert/3`, `rdn/1`, `extensions/2`, `key_identifier/1`,
`generate_rsa_key/2`, `extract_public_key/1`) below is that real source, unchanged except for the
module name, default path/name, and the shell-instructions message (which describes this
plugin's own config instead of Phoenix's `https:` Endpoint config). Write the file exactly as
given:

```elixir
defmodule Mix.Tasks.NewApiApp.Grpc.Gen.Cert do
  @shortdoc "Generates a self-signed certificate for gRPC TLS testing"

  @default_path "priv/cert/grpc_selfsigned"
  @default_name "Self-signed gRPC test certificate"
  @default_hostnames ["localhost"]

  @warning """
  WARNING: only use the generated certificate for testing in a closed network
  environment, such as running gRPC on `localhost`. For production, staging,
  or testing servers on the public internet, obtain a proper certificate,
  for example from a private CA or a service that issues them.
  """

  @moduledoc """
  Generates a self-signed certificate for gRPC TLS testing.

      $ mix new_api_app.grpc.gen.cert
      $ mix new_api_app.grpc.gen.cert my-service.localhost my-service.internal.example.com

  Creates a private key and a self-signed certificate in PEM format, for use
  as NewApiApp.GRPC.Credentials' certfile/keyfile/cacertfile config.

  #{@warning}

  ## Arguments

  The list of hostnames, if none are specified, defaults to:

    * #{Enum.join(@default_hostnames, "\n  * ")}

  Other (optional) arguments:

    * `--output` (`-o`): the path and base filename for the certificate and
      key (default: #{@default_path})
    * `--name` (`-n`): the Common Name value in the certificate's subject
      (default: "#{@default_name}")

  Requires OTP 21.3 or later.
  """

  use Mix.Task
  import Mix.Generator

  @doc false
  def run(all_args) do
    {opts, args} =
      OptionParser.parse!(
        all_args,
        aliases: [n: :name, o: :output],
        strict: [name: :string, output: :string]
      )

    path = opts[:output] || @default_path
    name = opts[:name] || @default_name
    hostnames = if args == [], do: @default_hostnames, else: args

    {certificate, private_key} = certificate_and_key(2048, name, hostnames)

    keyfile = path <> "_key.pem"
    certfile = path <> ".pem"

    create_file(
      keyfile,
      :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, private_key)])
    )

    create_file(
      certfile,
      :public_key.pem_encode([{:Certificate, certificate, :not_encrypted}])
    )

    print_shell_instructions(keyfile, certfile)
  end

  @doc false
  def certificate_and_key(key_size, name, hostnames) do
    private_key =
      case generate_rsa_key(key_size, 65537) do
        {:ok, key} ->
          key

        {:error, :not_supported} ->
          Mix.raise("""
          Failed to generate an RSA key pair.

          This Mix task requires Erlang/OTP 20 or later. Please upgrade to a
          newer version, or use another tool, such as OpenSSL, to generate a
          certificate.
          """)
      end

    public_key = extract_public_key(private_key)

    certificate =
      public_key
      |> new_cert(name, hostnames)
      |> :public_key.pkix_sign(private_key)

    {certificate, private_key}
  end

  defp print_shell_instructions(keyfile, certfile) do
    Mix.shell().info("""

    Update config/dev.exs (and config/test.exs) with:

      config :new_api_app, NewApiApp.GRPC.Credentials,
        certfile: "#{certfile}",
        keyfile: "#{keyfile}",
        cacertfile: "#{certfile}"

    #{@warning}
    """)
  end

  require Record

  # RSA key pairs

  Record.defrecordp(
    :rsa_private_key,
    :RSAPrivateKey,
    Record.extract(:RSAPrivateKey, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  Record.defrecordp(
    :rsa_public_key,
    :RSAPublicKey,
    Record.extract(:RSAPublicKey, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  defp generate_rsa_key(keysize, e) do
    private_key = :public_key.generate_key({:rsa, keysize, e})
    {:ok, private_key}
  rescue
    FunctionClauseError ->
      {:error, :not_supported}
  end

  defp extract_public_key(rsa_private_key(modulus: m, publicExponent: e)) do
    rsa_public_key(modulus: m, publicExponent: e)
  end

  # Certificates

  Record.defrecordp(
    :otp_tbs_certificate,
    :OTPTBSCertificate,
    Record.extract(:OTPTBSCertificate, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  Record.defrecordp(
    :signature_algorithm,
    :SignatureAlgorithm,
    Record.extract(:SignatureAlgorithm, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  Record.defrecordp(
    :validity,
    :Validity,
    Record.extract(:Validity, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  Record.defrecordp(
    :otp_subject_public_key_info,
    :OTPSubjectPublicKeyInfo,
    Record.extract(:OTPSubjectPublicKeyInfo, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  Record.defrecordp(
    :public_key_algorithm,
    :PublicKeyAlgorithm,
    Record.extract(:PublicKeyAlgorithm, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  Record.defrecordp(
    :extension,
    :Extension,
    Record.extract(:Extension, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  Record.defrecordp(
    :basic_constraints,
    :BasicConstraints,
    Record.extract(:BasicConstraints, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  Record.defrecordp(
    :attr,
    :AttributeTypeAndValue,
    Record.extract(:AttributeTypeAndValue, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  # OID values
  @rsaEncryption {1, 2, 840, 113_549, 1, 1, 1}
  @sha256WithRSAEncryption {1, 2, 840, 113_549, 1, 1, 11}

  @basicConstraints {2, 5, 29, 19}
  @keyUsage {2, 5, 29, 15}
  @extendedKeyUsage {2, 5, 29, 37}
  @subjectKeyIdentifier {2, 5, 29, 14}
  @subjectAlternativeName {2, 5, 29, 17}

  @organizationName {2, 5, 4, 10}
  @commonName {2, 5, 4, 3}

  @serverAuth {1, 3, 6, 1, 5, 5, 7, 3, 1}
  @clientAuth {1, 3, 6, 1, 5, 5, 7, 3, 2}

  defp new_cert(public_key, common_name, hostnames) do
    <<serial::unsigned-64>> = :crypto.strong_rand_bytes(8)

    today = Date.utc_today()

    not_before =
      today
      |> Date.to_iso8601(:basic)
      |> String.slice(2, 6)

    not_after =
      today
      |> Date.add(365)
      |> Date.to_iso8601(:basic)
      |> String.slice(2, 6)

    otp_tbs_certificate(
      version: :v3,
      serialNumber: serial,
      signature: signature_algorithm(algorithm: @sha256WithRSAEncryption),
      issuer: rdn(common_name),
      validity:
        validity(
          notBefore: {:utcTime, ~c"#{not_before}000000Z"},
          notAfter: {:utcTime, ~c"#{not_after}000000Z"}
        ),
      subject: rdn(common_name),
      subjectPublicKeyInfo:
        otp_subject_public_key_info(
          algorithm: public_key_algorithm(algorithm: @rsaEncryption),
          subjectPublicKey: public_key
        ),
      extensions: extensions(public_key, hostnames)
    )
  end

  defp rdn(common_name) do
    {:rdnSequence,
     [
       [attr(type: @organizationName, value: {:utf8String, "Phoenix Framework"})],
       [attr(type: @commonName, value: {:utf8String, common_name})]
     ]}
  end

  defp extensions(public_key, hostnames) do
    [
      extension(
        extnID: @basicConstraints,
        critical: true,
        extnValue: basic_constraints(cA: false)
      ),
      extension(
        extnID: @keyUsage,
        critical: true,
        extnValue: [:digitalSignature, :keyEncipherment]
      ),
      extension(
        extnID: @extendedKeyUsage,
        critical: false,
        extnValue: [@serverAuth, @clientAuth]
      ),
      extension(
        extnID: @subjectKeyIdentifier,
        critical: false,
        extnValue: key_identifier(public_key)
      ),
      extension(
        extnID: @subjectAlternativeName,
        critical: false,
        extnValue: Enum.map(hostnames, &{:dNSName, String.to_charlist(&1)})
      )
    ]
  end

  defp key_identifier(public_key) do
    :crypto.hash(:sha, :public_key.der_encode(:RSAPublicKey, public_key))
  end
end
```

Note: `rdn/1`'s `"Phoenix Framework"` organization-name string is copied verbatim from the real
source and is cosmetic (it's the `O=` field of a locally-generated, self-signed dev/test
certificate's subject — no client or server in this plugin's own code inspects it). Leave it
as-is rather than inventing a capstone-specific string not present in the verified original,
unless you specifically want to change it — either is fine, it has zero functional effect.

- [ ] **Step 2: Generate the shipped test/dev cert fixture**

```bash
cd priv/meta/grpc_component
mix new_api_app.grpc.gen.cert
```

Expected: `priv/cert/grpc_selfsigned.pem` and `priv/cert/grpc_selfsigned_key.pem` created, plus
the shell instructions printed. Confirm the cert is valid and covers `localhost`:

```bash
openssl x509 -in priv/cert/grpc_selfsigned.pem -noout -text | grep -A2 "Subject Alternative Name"
cd -
```

Expected: shows `DNS:localhost`.

- [ ] **Step 3: Verify it compiles**

```bash
cd priv/meta/grpc_component
mix compile --warnings-as-errors
cd -
```

- [ ] **Step 4: Commit**

```bash
git add priv/meta/grpc_component/lib/mix/tasks/new_api_app.grpc.gen.cert.ex \
        priv/meta/grpc_component/priv/cert/grpc_selfsigned.pem \
        priv/meta/grpc_component/priv/cert/grpc_selfsigned_key.pem
git commit -m "feat(plugin): add mix new_api_app.grpc.gen.cert and a committed test/dev cert fixture"
```

---

### Task 5: `mix <app>.grpc.gen` (protoc wrapper)

**Files:**
- Create: `priv/meta/grpc_component/lib/mix/tasks/new_api_app.grpc.gen.ex`

**Interfaces:**
- Produces: `mix new_api_app.grpc.gen` (documented in the README, Task 6).

- [ ] **Step 1: Confirm `protoc` and `protoc-gen-elixir` are available**

```bash
protoc --version
protoc-gen-elixir --version
```

If either is missing, install them (`brew install protobuf` for `protoc` on macOS;
`mix escript.install hex protobuf` for `protoc-gen-elixir`, per the `protobuf` package's own
installation docs) before continuing — this task's own verification step needs both.

- [ ] **Step 2: Create `lib/mix/tasks/new_api_app.grpc.gen.ex`**

```elixir
defmodule Mix.Tasks.NewApiApp.Grpc.Gen do
  @shortdoc "Compiles .proto files into Elixir gRPC service/message code"

  @moduledoc """
  Compiles every .proto file under priv/protos/ into
  lib/new_api_app/grpc/generated/.

  Requires `protoc` and `protoc-gen-elixir` installed on PATH — this task
  wraps the invocation, it does not install the compiler toolchain itself.
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
      args = ["--elixir_out=plugins=grpc:#{@out_dir}", "--proto_path=#{@proto_dir}"] ++ protos

      case System.cmd("protoc", args, stderr_to_stdout: true) do
        {output, 0} -> Mix.shell().info(output)
        {output, code} -> Mix.raise("protoc exited with status #{code}:\n#{output}")
      end
    end
  end
end
```

- [ ] **Step 3: Verify it works against a real, trivial `.proto` file**

This is the empirical verification the design spec explicitly flagged as unchecked — do it for
real, don't skip it.

```bash
cd priv/meta/grpc_component
mkdir -p priv/protos
cat > priv/protos/smoke.proto <<'EOF'
syntax = "proto3";

package smoke;

service Smoke {
  rpc Ping (PingRequest) returns (PingReply) {}
}

message PingRequest {
  string message = 1;
}

message PingReply {
  string message = 1;
}
EOF

mix new_api_app.grpc.gen
```

Expected: `lib/new_api_app/grpc/generated/smoke.pb.ex` (or similar, matching whatever
`protoc-gen-elixir` actually names its output) is created and contains real Elixir module
definitions (a `Smoke.PingRequest` struct, a `Smoke.Smoke.Service` behaviour module, etc.).
**If the exact flags in Step 2's code don't produce valid output, fix them based on what you
observe** (check `protoc-gen-elixir --help` or its own README for the correct current flag
names) — the spec explicitly did not verify this, so don't force a wrong guess to "pass."

```bash
mix compile --warnings-as-errors
```

Expected: the generated code compiles cleanly alongside the rest of the project.

- [ ] **Step 4: Remove the smoke-test fixture — it must not ship in the plugin**

```bash
rm -rf priv/protos lib/new_api_app/grpc/generated
cd -
```

Per the Global Constraints, no `.proto` file or generated service code ships in
`priv/meta/grpc_component/` — this was purely to verify Step 2's task works, not a shipped
fixture.

- [ ] **Step 5: Commit**

```bash
git add priv/meta/grpc_component/lib/mix/tasks/new_api_app.grpc.gen.ex
git commit -m "feat(plugin): add mix new_api_app.grpc.gen, wrapping protoc"
```

---

### Task 6: Shipped test and the README worked example

**Files:**
- Create: `priv/meta/grpc_component/test/grpc/client_test.exs`
- Modify: `priv/meta/grpc_component/README.md`

**Interfaces:**
- Consumes: `NewApiApp.GRPC.Client.connect/1` (Task 3), the committed cert fixture (Task 4).
- Produces: a fully self-running, tested `grpc_component`, ready for Task 7's `derive`.

- [ ] **Step 1: Create `test/grpc/client_test.exs`**

Per the Global Constraints, this test does NOT call `start_supervised!` on anything —
`application.ex` already starts `GRPC.Server.Supervisor` unconditionally, including under
`:test` (where `mix test` boots the full app before any test body runs):

```elixir
defmodule NewApiApp.GRPC.ClientTest do
  use ExUnit.Case, async: true

  alias NewApiApp.GRPC.Client

  test "connects to the app's own already-running gRPC server over TLS" do
    port = Application.fetch_env!(:new_api_app, NewApiApp.GRPC.Endpoint)[:port]

    assert {:ok, channel} = Client.connect("localhost:#{port}")
    assert %GRPC.Channel{} = channel
  end
end
```

- [ ] **Step 2: Run it**

```bash
cd priv/meta/grpc_component
mix test test/grpc/client_test.exs
cd -
```

Expected: PASS — proving the real, TLS-wrapped `GRPC.Server.Supervisor` genuinely started (via
`application.ex`, using the committed cert fixture) and a real client connection over TLS
succeeds against the empty `NewApiApp.GRPC.Endpoint`. If this fails with a certificate/hostname
error, check that the committed cert's `subjectAltName` actually covers `localhost` (verified in
Task 4 Step 3) and that the client's `cacertfile` correctly points at the same cert.

- [ ] **Step 3: Append the README section**

Add to the end of `priv/meta/grpc_component/README.md`:

````markdown
## gRPC

This project has both a gRPC server (`NewApiApp.GRPC.Endpoint`) and a gRPC client
(`NewApiApp.GRPC.Client`), TLS-required on both sides — no plaintext fallback.

### Setup

A self-signed dev/test certificate is already generated and committed
(`priv/cert/grpc_selfsigned.pem`/`grpc_selfsigned_key.pem`) — for production, replace these paths
in `config/runtime.exs` with real certificate paths (env vars), the same way `NewApiApp.Repo`'s
production credentials are already handled there.

To regenerate the dev/test cert (e.g. to add more hostnames):

```bash
mix new_api_app.grpc.gen.cert my-service.localhost
```

To compile `.proto` files (requires `protoc` and `protoc-gen-elixir` installed — see
https://grpc.io/docs/protoc-installation/ and the `protobuf` Hex package's own install docs):

```bash
mix new_api_app.grpc.gen
```

This compiles every `.proto` file under `priv/protos/` into `lib/new_api_app/grpc/generated/`.

### Worked example

```elixir
# priv/protos/greeter.proto
syntax = "proto3";

package greeter;

service Greeter {
  rpc SayHello (HelloRequest) returns (HelloReply) {}
}

message HelloRequest {
  string name = 1;
}

message HelloReply {
  string message = 1;
}
```

```bash
mix new_api_app.grpc.gen
```

```elixir
# A developer's own service implementation — NOT shipped by this plugin.
defmodule NewApiApp.Greeter.Server do
  use GRPC.Server, service: Greeter.Greeter.Service

  @impl true
  def say_hello(request, _stream) do
    %Greeter.HelloReply{message: "Hello, #{request.name}!"}
  end
end
```

Add your service to `NewApiApp.GRPC.Endpoint`:

```elixir
defmodule NewApiApp.GRPC.Endpoint do
  use GRPC.Endpoint

  run [NewApiApp.Greeter.Server]
end
```

Call it from a client (this project's own, or a different one entirely):

```elixir
{:ok, channel} = NewApiApp.GRPC.Client.connect("localhost:50051")
{:ok, reply} = channel |> Greeter.Greeter.Stub.say_hello(%Greeter.HelloRequest{name: "World"})
```

**Limitations:** no connection pooling (`NewApiApp.GRPC.Client.connect/1` is a one-shot,
stateless helper — build a pooled/supervised channel manager yourself if needed); no gRPC
reflection or health-checking services; no streaming RPC example (this plugin's worked example
covers a basic unary call only — `grpc`/`protobuf` fully support streaming, just not demonstrated
here); no mutual TLS (the server doesn't verify a client certificate) — extend
`NewApiApp.GRPC.Credentials.server_credential/0` yourself if you need that.
````

- [ ] **Step 4: Verify it compiles**

```bash
cd priv/meta/grpc_component
mix compile --warnings-as-errors
cd -
```

- [ ] **Step 5: Commit**

```bash
git add priv/meta/grpc_component/test/grpc/client_test.exs \
        priv/meta/grpc_component/README.md
git commit -m "feat(plugin): add the shipped gRPC client/server test and README worked example"
```

---

### Task 7: Derive the `:grpc` manifest and record real baseline hashes

**Files:**
- Create: `priv/meta/meta_grpc/manifest.exs`, `priv/meta/meta_grpc/files/*.eex` (all `derive` output — do not hand-author)
- Modify: `priv/baselines.exs` (rewritten by `mix capstone.baseline.record`)

**Interfaces:**
- Consumes: the finished `priv/meta/grpc_component/` tree (Tasks 1-6).
- Produces: `priv/meta/meta_grpc/manifest.exs`, consumed by Task 8's round-trip test and Task 9's structural toolchain test.

- [ ] **Step 1: Derive**

```bash
mix capstone.plugin.derive grpc
```

Expected: `wrote priv/meta/meta_grpc/manifest.exs` plus a file/dep count.

- [ ] **Step 2: Inspect the manifest for correctness**

```bash
cat priv/meta/meta_grpc/manifest.exs
```

Verify:
- `deps:` contains exactly three entries: `grpc`, `grpc_server`, `protobuf`, matching `mix.exs`'s
  declaration order.
- Every `lib/new_api_app/grpc/*.ex`, `lib/mix/tasks/new_api_app.grpc.*.ex`, `test/grpc/*_test.exs`,
  and both `priv/cert/grpc_selfsigned*.pem` files appear as `{"...", :sole_owner}`.
- `README.md` appears as `:contributes`.
- `config/config.exs` appears as `:contributes` with `:before_import` placement.
- `lib/APP/application.ex` appears as `:contributes` with a `child:` entry (a single templated
  string, NOT a list — this plugin adds exactly one child, unlike `:cqrs`'s early 3-child
  mistake) — NOT `:manual`. If it IS `:manual`, re-check Task 2 Step 3 for an accidental extra
  edit to `application.ex` and redo it, then re-run `derive`.

- [ ] **Step 3: Re-derive `:cache` and `:cqrs` too, confirming no diff**

```bash
mix capstone.plugin.derive cache
mix capstone.plugin.derive cqrs
git diff --stat priv/meta/meta_cache priv/meta/meta_cqrs
```

Expected: no diff — this task's work is additive, unrelated plugins shouldn't move.

- [ ] **Step 4: Record real baseline hashes**

```bash
mix capstone.baseline.record
```

- [ ] **Step 5: Verify `priv/baselines.exs`'s new `:grpc` entry looks sane**

```bash
mix run -e '
entry = Capstone.Baseline.read!("priv/baselines.exs").grpc
IO.inspect(entry.derived_from)
IO.inspect(map_size(entry.files))
IO.inspect(entry.path)
'
```

Expected: `:api`, a file count matching the manifest's file count plus every unchanged baseline
file, `"priv/meta/grpc_component"`.

- [ ] **Step 6: Commit (leave the root snapshot archives untracked for Task 10)**

```bash
git add priv/meta/meta_grpc priv/meta/meta_cache priv/meta/meta_cqrs priv/baselines.exs
git status --porcelain  # confirm the *_*.tar.gz files show as untracked (??), not staged
git commit -m "feat(plugin): derive the :grpc manifest, record real baseline hashes"
```

---

### Task 8: Round-trip test for `:grpc`

**Files:**
- Create: `test/capstone/plugin/grpc_round_trip_test.exs`

**Interfaces:**
- Consumes: `priv/meta/meta_grpc/manifest.exs`, `priv/meta/grpc_component/` (Task 7).

- [ ] **Step 1: Write the test file**

Modeled on `test/capstone/plugin/cqrs_round_trip_test.exs`'s final, simplified 3-test shape (no
`:manual`-anchor special-casing needed — `:grpc` adds exactly one supervision child, so
`application.ex` reproduces cleanly like every other file):

```elixir
defmodule Capstone.Plugin.GrpcRoundTripTest do
  # async: false — copies real trees under priv/meta.
  use ExUnit.Case, async: false

  alias Capstone.Baseline
  alias Capstone.Plugin.Apply

  @baseline "priv/meta/baseline_api"
  @plugin "priv/meta/meta_grpc"
  @raw "priv/meta/grpc_component"

  setup do
    target = Path.join(System.tmp_dir!(), "grpc-round-trip-#{System.unique_integer([:positive])}")
    File.cp_r!(@baseline, target)
    on_exit(fn -> File.rm_rf!(target) end)

    {:ok, target: target}
  end

  test "applying meta_grpc to baseline_api reproduces grpc_component", %{target: target} do
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
    other = Path.join(System.tmp_dir!(), "grpc-other-#{System.unique_integer([:positive])}")
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

    File.rename!(Path.join(other, "lib/new_api_app"), Path.join(other, "lib/other_app"))

    for file <- Path.wildcard(Path.join(other, "lib/other_app/**/*.ex")) do
      File.write!(file, String.replace(File.read!(file), "NewApiApp", "OtherApp"))
    end

    {:ok, _} = Apply.run(@plugin, other)

    assert File.read!(Path.join(other, "lib/other_app/grpc/client.ex")) =~
             "defmodule OtherApp.GRPC.Client"

    refute File.exists?(Path.join(other, "lib/new_api_app/grpc/client.ex"))
  end
end
```

If Task 7's manifest inspection found `application.ex` unexpectedly fell back to `:manual`,
STOP — don't write this test's base case expecting a clean reproduction; re-check Task 2 first,
since a single-child edit should not need any special-casing.

- [ ] **Step 2: Run it**

```bash
mix test test/capstone/plugin/grpc_round_trip_test.exs
```

Expected: 3/3 PASS. If the base reproduction test fails, the failure names the differing file
path — re-check Task 7's manifest inspection rather than patching this test to match a wrong
reproduction.

- [ ] **Step 3: Commit**

```bash
git add test/capstone/plugin/grpc_round_trip_test.exs
git commit -m "test(plugin): add a round-trip test for the :grpc plugin"
```

---

### Task 9: `:grpc` structural toolchain test

**Files:**
- Modify: `test/integration/plugin_lifecycle_test.exs`

**Interfaces:**
- Consumes: `priv/baselines.exs`'s `:grpc` entry, `priv/meta/meta_grpc/manifest.exs` (Task 7).

Per the Global Constraints, this test needs the local-packaging workaround if `:grpc` isn't
published yet: `mix capstone.plugin.package grpc`, copy the archive into
`~/Library/Caches/capstone/plugins/`, remove any stale same-plugin archives there first.

- [ ] **Step 1: Add the new `:grpc` toolchain test**

Insert into `test/integration/plugin_lifecycle_test.exs`, after the existing toolchain tests
(before the `assert_placed_not_marked/3` helper's `defp`):

```elixir
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
```

`assert_placed_not_marked/3`'s exact assertion signature — read the existing helper (used by the
`:cache`/`:cqrs` toolchain tests already in this file) before assuming its exact call shape;
adapt if it differs from what's shown here.

- [ ] **Step 2: Run it**

```bash
mix test test/integration/plugin_lifecycle_test.exs --include toolchain
```

(Or the specific file:line form for just this new test, if you want a faster iteration loop —
find the right line number by reading the file after inserting.)

Expected: PASS. Budget a couple of minutes (the inner `mix test` does its own `deps.get`/
`deps.compile`).

- [ ] **Step 3: Commit**

```bash
git add test/integration/plugin_lifecycle_test.exs
git commit -m "test(plugin): add a structural toolchain test for the :grpc plugin"
```

---

### Task 10: Package, publish, and run the full gate suite

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

Fix anything that fails before continuing. None of Tasks 1-9 added code under this repo's own
`lib/` (everything new lives under `priv/meta/`, which is data, not compiled capstone source), so
`mix coveralls`' baseline should be unaffected.

- [ ] **Step 2: Package the plugin**

```bash
mix capstone.plugin.package grpc
```

Expected: `wrote priv/plugins/grpc-<elixir>-<capstone>-<sha>.tar.gz`. Confirm nothing new is
staged:

```bash
git status --porcelain priv/plugins/
```

- [ ] **Step 3: STOP — get explicit human sign-off before publishing**

Creating and uploading a GitHub release is a side effect visible to others, outside this
worktree — per this session's own established practice, this step requires the human partner's
explicit go-ahead before proceeding. Present what's about to happen (the release notes, the
files to upload) and wait for confirmation.

- [ ] **Step 4: Determine the current version and create a GitHub release**

```bash
version=$(cat .version)
echo "$version"
gh release create "v$version" \
  --repo wimwian-org/capstone \
  --title "v$version" \
  --notes "A new :grpc plugin — gRPC server and client infrastructure with TLS required by default, protoc/cert-generation mix tasks." \
  --target dev
```

If a release for this exact version tag already exists, use `gh release upload "v$version" <files>`
against the existing release instead of `gh release create`.

- [ ] **Step 5: Upload the archive set**

```bash
gh release upload "v$version" ./*_"$version"_*.tar.gz --repo wimwian-org/capstone
gh release upload "v$version" priv/plugins/grpc-*.tar.gz --repo wimwian-org/capstone
```

- [ ] **Step 6: Clean up the untracked root-level snapshot archives**

```bash
rm -f ./*_"$version"_*.tar.gz
git status --porcelain
```

- [ ] **Step 7: Final sanity check — verify the plugin downloads and applies from the release**

```bash
rm -rf ~/Library/Caches/capstone
mix run -e '
dir = Capstone.Plugin.Registry.default_dir()
Capstone.Plugin.Remote.sync!(:grpc, dir)
IO.inspect(File.ls!(dir))
'
rm -rf ~/Library/Caches/capstone
```

Expected: the listed files include a `grpc-*.tar.gz` matching the version just packaged.

- [ ] **Step 8: Final commit if anything changed during gate fixes**

```bash
git status --porcelain
# If clean, nothing to commit.
# If Step 1 required fixes, commit them:
git add -A
git commit -m "chore(plugin): fix gate failures found while finishing the :grpc plugin"
```
