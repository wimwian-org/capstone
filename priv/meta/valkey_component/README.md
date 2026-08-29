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

## Valkey

Valkey is the default KV platform, reached via `NewApiApp.Valkey`, a thin
Redix client (see `NewApiApp.Valkey.get/1` and `.set/3`).

In dev and test, `compose.yaml`'s `valkey` service is up on `localhost:6379`
with no auth, so nothing extra needs to be set up locally. In prod, the same
image runs as this service's sidecar — set `VALKEY_HOST`/`VALKEY_PORT` if it
isn't reachable at the default `localhost:6379`.
