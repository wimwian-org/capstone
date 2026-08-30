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

Valkey is the default KV platform, reached through `NewApiApp.Valkey.Cache` —
a two-level cache, not a thin client. Reads check an in-VM L1 (Nebulex local)
first and fall through to Valkey (L2) on a miss, backfilling L1; writes land
in L1 immediately and then go to L2 through a circuit breaker. A
`NewApiApp.Valkey.Invalidator` broadcast keeps other nodes' L1 copies from
going stale.

```elixir
NewApiApp.Valkey.Cache.put("k", "v") # also accepts `ttl:`
NewApiApp.Valkey.Cache.get("k") #=> "v"
NewApiApp.Valkey.Cache.delete("k")
NewApiApp.Valkey.Cache.put_new("k", "v") #=> true | false
NewApiApp.Valkey.Cache.incr("counter", 2) #=> 2
NewApiApp.Valkey.Cache.decr("counter") #=> 1
```

### What happens when Valkey is down

`NewApiApp.Valkey.Breaker` wraps every L2 call in a timeout and a circuit
breaker, and the six operations split into two groups:

* `get/1`, `put/3` and `delete/1` **degrade**. When the circuit is open or the
  call fails they return a safe default (`nil` or `:ok`) and the cache carries
  on as L1-only, so a dead sidecar slows the app down rather than breaking it.
  Note that a `put/3` in this state reaches L1 but not Valkey.
* `put_new/3`, `incr/2` and `decr/2` **raise**. There is no safe default to
  invent for them: any answer this side could fabricate ("yes, it was new",
  "the counter is 5") would be wrong the moment L2 comes back, so callers get
  the failure instead of a lie. See `NewApiApp.Valkey.Breaker`'s moduledoc for
  the full reasoning.

Note also that a value backfilled into L1 by `get/1` lives there for up to
`NewApiApp.Valkey.Cache`'s configured `:default_ttl`, even if the original
`put/3` asked for something shorter — the backfill does not carry the
remaining L2 TTL across.

In dev and test, `compose.yaml`'s `valkey` service is up on `localhost:6379`
with no auth, so nothing extra needs to be set up locally. In prod, the same
image runs as this service's sidecar — set `VALKEY_HOST`/`VALKEY_PORT` if it
isn't reachable at the default `localhost:6379`.

Data written to Valkey persists across a container restart via a bind mount
at `.valkey_data/` (gitignored) — the container's own default `SAVE`
schedule is what actually flushes to disk; a hard `kill -9` between saves can
still lose the most recent writes, same as any Redis-protocol store running
without `appendonly yes`.

If you're working on this plugin itself (not just using it): running the
sidecar leaves a binary RDB snapshot in `.valkey_data/`. Delete that
directory before running `mix capstone.plugin.derive valkey` from the repo
root — the raw tree walk that builds the derived plugin does not skip
binary files, and one left behind there will fail the derive.
