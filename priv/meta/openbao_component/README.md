# NewApiApp

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

## OpenBao

Secrets are read from an OpenBao (Vault-compatible) sidecar via
`NewApiApp.Vault.read_secret/2`, which talks to its KV v2 HTTP API.
`NewApiApp.Vault.health/0` checks the sidecar's own health endpoint (no auth
header needed) if you want a readiness probe.

In dev and test, `compose.yaml`'s `openbao` service runs in dev mode with a
fixed root token, so nothing extra needs to be set up locally. In prod,
`OPENBAO_ADDR` must point at a real OpenBao deployment — this plugin never
starts one.

### IMPORTANT: the app will not boot without OpenBao

`NewApiApp.Vault.Auth` is **fail-closed** and starts first in the supervision
tree. Under `OPENBAO_METHOD=approle` it performs its first login
*synchronously* during `Application.start/2`; if OpenBao is unreachable, the
credentials are wrong, or AppRole was never enabled, that login fails and the
whole application refuses to start. This is deliberate — an app that boots
without its secrets is worse than one that does not boot — but it means
OpenBao is a hard startup dependency in production, not a soft one. Order your
deploy so the sidecar is reachable before the app starts, and expect a crash
loop rather than a degraded process if it is not.

Only the *first* login is fail-closed. Once it succeeds, later renewal
failures retry forever in the background and never take the app down: a lease
expiring mid-run is not the same as never having had credentials at all.

Under the default `OPENBAO_METHOD=token` there is no login round-trip, so this
gate does not apply — but a missing `OPENBAO_TOKEN` still raises during
`config/runtime.exs` evaluation, which is likewise a boot failure.

### Auth methods

`OPENBAO_METHOD` selects how the app authenticates. Anything other than these
two values raises at boot with a message naming them:

* `token` (default) — a static token from `OPENBAO_TOKEN`. Zero setup, and
  what dev and test use against the dev-mode sidecar.
* `approle` — `OPENBAO_ROLE_ID` and `OPENBAO_SECRET_ID` are posted to
  `/v1/auth/approle/login` and the resulting lease is renewed automatically.
  `OPENBAO_MOUNT` (default `approle`) names the auth mount.

`OPENBAO_ADDR` (default `http://localhost:8200`) applies to both.

### Bootstrapping AppRole locally

Dev-mode OpenBao auto-mounts KV v2 at `secret/` but does *not* enable AppRole.
With the sidecar up (`podman-compose up -d openbao`):

```sh
mix openbao.setup \
  --base-url http://localhost:8200 \
  --root-token new_api_app-dev-root-token
```

It enables the AppRole auth method, creates a role and a policy granting read
on `secret/data/*`, then prints a `role_id` and `secret_id` to drop into
`config/dev.exs` (or export as `OPENBAO_ROLE_ID`/`OPENBAO_SECRET_ID`). The
task is idempotent apart from rotating the `secret_id` on every run.
