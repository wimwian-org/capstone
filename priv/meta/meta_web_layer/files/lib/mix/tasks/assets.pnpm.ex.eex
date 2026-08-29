defmodule Mix.Tasks.Assets.Pnpm do
  @moduledoc """
  Runs a pnpm script inside `assets/`. Usage: `mix assets.pnpm <script> [-- extra args]`.

  Internal building block for the `assets.check`/`assets.lint`/`assets.format`/`assets.test`/
  `assets.test.coverage`/`assets.test.e2e` aliases — call those directly rather than this task,
  unless you need a `package.json` script this scaffold didn't wire an alias for.
  """
  @shortdoc "Run a pnpm script in assets/"
  use Mix.Task

  @impl true
  def run([script | rest]) do
    assets_dir = Path.join(File.cwd!(), "assets")

    unless File.dir?(assets_dir) do
      Mix.raise("assets/ not found — this project has no live_svelte asset pipeline (07-assets.md)")
    end

    {_output, exit_code} =
      System.cmd("pnpm", ["run", script | rest],
        cd: assets_dir,
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    if exit_code != 0 do
      Mix.raise("pnpm run #{script} (in assets/) failed with exit code #{exit_code}")
    end
  end

  def run([]) do
    Mix.raise("Usage: mix assets.pnpm <script> [-- extra args]")
  end
end
