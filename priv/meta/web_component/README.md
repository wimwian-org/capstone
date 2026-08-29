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

## Web assets (LiveView + Svelte)

This project ships a `live_svelte` asset pipeline: Vite bundles a Svelte 5 UI alongside Phoenix
LiveView, with pnpm as the JS package manager for everything under `assets/`.

Run `mix assets.setup` once before first use to install the pnpm-managed dependencies (`mix setup`
already calls it, so a fresh clone only needs `mix setup`). `mix phx.server` then starts the Vite
dev server automatically, as a dev-only Phoenix watcher (`NewApiApp.ViteWatcher`, port 5173) —
there is nothing extra to start by hand.

### `assets.*` aliases

* `mix assets.setup` — `pnpm install`
* `mix assets.build` — a one-off production Vite build (also `mix assets.deploy`, which `mix
  release` runs)
* `mix assets.check` — `svelte-check` (TypeScript/Svelte type checking)
* `mix assets.lint` — ESLint plus a Prettier `--check`
* `mix assets.format` — `prettier --write`
* `mix assets.test` — the Vitest unit suite
* `mix assets.test.coverage` — the Vitest suite with coverage
* `mix assets.test.e2e` — Playwright end-to-end tests; run `pnpm exec playwright install` once
  from `assets/` first, to fetch the browsers Playwright needs
