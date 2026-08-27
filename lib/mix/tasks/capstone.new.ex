defmodule Mix.Tasks.Capstone.New do
  @shortdoc "Bootstraps a new Capstone project"

  @moduledoc """
  Generates a stock Elixir or Phoenix project, adds the `capstone` dev
  dependency, writes `target.exs`, and fetches and compiles dependencies.

      mix capstone.new --path TARGET_EXS

  `TARGET_EXS` is a `target.exs`-shaped file — `schema_version`, `base`
  (`:api`, `:web` or `:both`), `project: [name:, github_org:, module:, app:]`,
  `plugins: []` — read via `Capstone.Config`, the same reader `capstone`
  itself uses. There is no `:otp` value in that schema, so this task cannot
  generate a bare, non-Phoenix OTP app.

  ## Post-MVP continuation — verified working, deliberately NOT implemented

  The four-step sequence that hands off to `mix capstone.gen` once it exists is
  recorded verbatim, with the reason each step is load-bearing, in this
  project's `README.md` under "Post-MVP continuation".

  It is kept there rather than here because `Capstone.BoundaryGuard`
  substring-scans `lib/**/*.ex` — documentation and comments included — and
  two of those four calls are on its banned list. Prose naming a banned API
  is indistinguishable from a call to it, which is the point: the guard
  exists because a rule expressed only in prose rots.

  Running that sequence today buys nothing — `capstone.gen` does not exist — and
  `deps.compile` prunes every archive off the code path before it could.
  """

  use Mix.Task

  alias Capstone.New.Bootstrap
  alias Capstone.New.Options

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  # coveralls-ignore-start
  # The one ignored line under `lib/capstone/new/` and this task. `@impl Mix.Task` fixes this
  # function's arity at 1, so there is no parameter through which a test could
  # inject a fake runner — covering it would mean really generating a project.
  # Everything it delegates to is covered in-process; see Capstone.New.Bootstrap.
  def run(argv), do: argv |> Options.parse!() |> Bootstrap.run(Bootstrap.defaults())
  # coveralls-ignore-stop
end
