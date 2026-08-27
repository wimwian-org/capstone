# Boilerplate

The tooling configuration every generated project inherits. These files are
**payload** — they are written into generated projects and are never used by
this repository, which uses its own copies at the root.

Editing anything here changes every future project's configuration. It does not
change this one.

## Naming

| Suffix       | Means                                                        |
| ------------ | ------------------------------------------------------------ |
| `*.eex`      | Carries `<%= @… %>` placeholders; rendered at generation time |
| no `.eex`    | Copied verbatim                                              |
| no leading `.` | Always — see below                                         |

**Nothing here starts with a dot**, even though most of these land in the target
as dotfiles (`.credo.exs`, `.doctor.exs`, `.formatter.exs`, `.gitignore`).
`mix archive.build` silently drops dotfiles under `priv/` unless
`--include-dot-files`, and `mix archive.install hex` passes no options — so a
file shipped as `.gitignore` would simply be absent, with no error. The
generator writes the leading dot when it renders. This is failure mode **F1**'s
neighbourhood and it was reproduced, not assumed.

## Assigns

Every template is rendered with exactly these:

| Assign        | Example  | Notes                                              |
| ------------- | -------- | -------------------------------------------------- |
| `@app`        | `my_app` | snake_case OTP application name, no colon          |
| `@module`     | `MyApp`  | CamelCase module prefix                            |
| `@github_org` | `acme`   | owner segment of the repository URL                |
| `@web?`       | `true`   | the project has a Phoenix web layer                |
| `@api?`       | `false`  | that web layer is API-only; only read when `@web?` |
| `@ecto?`      | `true`   | the project has a Repo — **independent of `@web?`** |

**`@ecto?` is orthogonal to `@web?`, and that is the point.** An OTP project can
have a Repo, and a Phoenix project can be generated with `--no-ecto`. Gating the
Ecto branches on `@web?` — as an earlier version of these templates did — leaves
an OTP-plus-Repo project with no `priv/*/migrations` formatter subdirectory, no
seeds input, no `MyApp.Repo` doctor ignore and no `release.ex` coverage skip.

`@api?` is the same shape one level down: an API-only project has no HEEx
templates, no `Phoenix.LiveView.HTMLFormatter`, no Gettext and no asset
pipeline, but it is still `@web?`.

| Branch gated on          | What it controls                                          |
| ------------------------ | --------------------------------------------------------- |
| `@ecto?`                 | `:ecto`/`:ecto_sql` formatter deps, migrations subdirectory, seeds input, `MyApp.Repo` doctor ignore, `release.ex` coverage skip |
| `@web?`                  | `:phoenix` formatter dep, `Endpoint`/`Router.Helpers` doctor ignores, `telemetry.ex` coverage skip |
| `@web?` and not `@api?`  | HEEx inputs and formatter plugin, Gettext doctor ignore, asset-pipeline gitignore entries |

## Contents

| Template                        | Rendered to             | What it configures                          |
| ------------------------------- | ----------------------- | ------------------------------------------- |
| `credo.exs.eex`                 | `.credo.exs`            | static analysis, and the comment-tag gate   |
| `credo/checks/tag_bug.ex.eex`   | `credo/checks/tag_bug.ex` | the `BUG` check Credo does not ship       |
| `credo/checks/tag_xxx.ex.eex`   | `credo/checks/tag_xxx.ex` | the `XXX` check Credo does not ship       |
| `doctor.exs.eex`                | `.doctor.exs`           | documentation coverage thresholds           |
| `coveralls.json.eex`            | `coveralls.json`        | `minimum_coverage: 100` and skip list       |
| `formatter.exs.eex`             | `.formatter.exs`        | formatter inputs and plugins                |
| `dialyzer_ignore.exs`           | `.dialyzer_ignore.exs`  | dialyzer suppressions (empty to start)      |
| `gitignore.eex`                 | `.gitignore`            | build artifacts, and web assets when `@web?` |

The two `credo/checks/` templates are not optional extras. `TODO`, `FIXME`,
`BUG` and `XXX` all fail a build in a Capstone project, but Credo only ships checks
for the first two — so without these files the generated `.credo.exs` would
reference modules that do not exist. They are namespaced to `<%= @module %>`
rather than to `Capstone`, because they are the generated project's code once
written.

## Testing

`test/boilerplate_test.exs` renders every template for both a `@web?` and a
non-`@web?` project and asserts the output parses as Elixir or JSON. Nothing
else in this repository ever evaluates these files, so without that test a typo
is found by the first person to generate a project.
