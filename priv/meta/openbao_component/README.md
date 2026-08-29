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

In dev and test, `compose.yaml`'s `openbao` service runs in dev mode with a
fixed root token, so nothing extra needs to be set up locally. In prod,
`OPENBAO_ADDR` and `OPENBAO_TOKEN` must point at a real OpenBao deployment —
this plugin never starts one.
