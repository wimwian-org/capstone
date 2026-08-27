# Goal

Capstone's goal is not to generate an Elixir/Phoenix project. Generating one is
the easy half, and `mix phx.new` already does it well. The goal is to generate a
project **and keep it upgradable for the rest of its life** — so that a project
scaffolded six months ago, since hand-edited by three people, can absorb a
plugin revision or a dependency bump without losing anyone's work.

Everything unusual in this codebase descends from that one sentence.

## Contents

The identifiers below are cited throughout the codebase — moduledocs under
`lib/` and assertions in `test/` reference decisions and goals by number, so
the ranges are listed here rather than left to be found.

- [The day-two problem](#the-day-two-problem) — the requirement, and why month six is the moment that hurts
- [Where the gap is](#where-the-gap-is) — `phx.new`, Igniter, Fireside, cruft and Rails, and exactly where each one stops
- [Why not full AI-based generation](#why-not-full-ai-based-generation) — determinism as an entailment of the update model, not a preference
- [What is built instead](#what-is-built-instead) — pointers into the README, which carries the mechanics
- [When a change will not apply](#when-a-change-will-not-apply) — the commented-`TODO(capstone)` answer, and the two alternatives that break the project
- [Comment-type-based actions](#comment-type-based-actions) — ten tags, four of which fail the build
- [Features](#features) — what the finished thing does, stated as capabilities rather than modules
- [The failure modes it exists to prevent](#the-failure-modes-it-exists-to-prevent) — inherited from earlier attempts
- [Failures encountered](#failures-encountered) — **E1–E11**, each reproduced rather than reasoned about
- [Decisions](#decisions) — the load-bearing ones, and what D20 costs
- [Numbered goals](#numbered-goals) — **G1–G10**, each a test rather than an aspiration
- [Opportunities](#opportunities) — what the architecture makes cheap, none of it committed work
- [Potential pitfalls](#potential-pitfalls) — where this is most likely to go wrong
- [Non-goals](#non-goals) — what Capstone deliberately does not do

---

## The day-two problem

A scaffolder is a birth event. You run it once, it writes a few hundred files,
and then it is gone. Every decision it made is now frozen into your repository,
and every improvement it learns afterwards is yours to re-apply by hand.

The moment that hurts is not minute zero. It is month six:

- Phoenix ships a new `endpoint.ex` shape and your generated one is three
  versions behind.
- You want to add caching to a project that was generated without it, and the
  wiring touches `application.ex`, `config/runtime.exs`, `mix.exs` and
  `compose.yaml` — four files you have since edited.
- A colleague generates a second project and gets a subtly different skeleton,
  because the generator moved on and yours did not.

The usual answer is "diff it against a fresh generation and merge by hand." That
answer scales to one project and one option. It does not scale to a team, a
plugin registry, or a scaffolder that is still learning.

**The distinguishing requirement is not generation. It is update.**

---

## Where the gap is

This is not an unsolved problem for want of trying. It is worth being specific
about what already exists and exactly where each one stops.

**`mix new` / `phx.new`** — the right skeletons, and Capstone composes on top of
them rather than replacing them. But they have no memory. They cannot tell you
what they wrote, at what version, or whether you have touched it since. There is
nothing to update _from_.

**[Igniter](https://github.com/ash-project/igniter)** — the best code-patching
framework in the ecosystem, and the reference for what patching an existing
project well looks like: composable tasks over a parsed project rather than
string surgery. Its gap is narrow and specific. `Rewrite.Source.file_changed?/1`
compares against a hash captured _during this run_; it detects concurrent
modification, not the edit you made last March. Cross-run edit detection — the
entire basis of a safe update — is outside its scope.

**[Fireside](https://github.com/ibarakaiev/fireside)** — the closest prior art,
and the source of the shape of `plugin.exs`. Its idea is
exactly the requirement: import plugins into an existing project together
with their dependencies, and upgrade them later. Its implementation is a
~1350-line proof of concept. We reproduced fourteen defects against Fireside
0.2.0, one of them disqualifying: it rewrites _every_ `.ex`, `.exs` file under
`lib/`, `test/` and `config/` using prefix matching on raw atom text, so a
plugin named `:auth` silently turns `:authorized` into `:tgtorized` in files
Fireside has never owned and will never hash. The idea survives; the
implementation could not be depended on.

**cookiecutter / cruft** — outside this ecosystem, and the closest thing to the
right update model anywhere: regenerate the old version, regenerate the new one,
diff _those_, apply the patch to the working tree. Capstone's update flow is
directly descended from it. What cruft cannot do is reason about Elixir. It
treats `mix.exs` as text, so it cannot add a dependency to a `deps/0` that a
human has reordered.

**Rails' `app:update`** — ships the honest behaviour (show the conflict, ask)
but has no story for third-party plugins, and Rails' framework-level
integration is not available to a scaffolder that sits outside the framework.

The missing piece, in all of them, is a file class none of them represents: the
file that **many plugins contribute to**. `router.ex`, `application.ex`,
`config/config.exs`, `mix.exs`, `package.json`, `compose.yaml` — each receives
contributions from the base _and_ from every feature you enable. A model with
only "this plugin owns this file" cannot express it; a model with only "patch
this text" cannot update it safely. Capstone's manifest records per-file
ownership mode — sole owner, contributor, or write-once seed — because that
distinction is the whole problem.

---

## Why not full AI-based generation

The obvious 2026 answer is to hand the whole thing to a model: describe the
project, let it write the files, let it write the upgrade too. Capstone
deliberately does not do this. **Generation is mechanical — there is no model in
the execution path.** Four reasons, in descending order of how load-bearing they
are.

### 1. The update model requires determinism, and a model cannot provide it

Capstone updates a project by regenerating the plugin _as it was at the
recorded version_, regenerating it _as it is now_, diffing those two, and
applying that patch to your working tree. That is the only mechanism that
survives hand-edited files, and it has a hard prerequisite: the same inputs must
produce byte-identical output, today and in eighteen months. No timestamps, no
randomness, no map iteration order in output — and no model, whose output is not
reproducible even against itself. A generator that cannot regenerate its own
history cannot compute a correct patch, and a scaffolder that cannot compute a
correct patch can only clobber.

This is not a preference. It is an entailment: without determinism there is no
three-way merge, and without a three-way merge there is no update.

### 2. It was tried before, and the failure is on the record

Capstone supersedes earlier attempts. One of them worked the way an AI-first
scaffolder would: options were large markdown documents that an agent read and
implemented. The recorded failure is blunt — _option documents were too large;
agents lost context; output was LLM-improvised and broke easily._ Two projects
generated from the same document were not the same project. That is
catalogued below as **F3**, and it is one of the named failure modes the
current architecture exists to make structurally impossible.

### 3. The diff is the definition — observed, never guessed

A plugin here is not a prose description of a feature. It is the **observed
diff** between a vanilla `mix new` / `phx.new` baseline and a real, compiling,
tested project that has the feature. `mix capstone.plugin.derive` computes
that diff and emits the plugin from it; the suite asserts the derivation still
reproduces the checked-in result. The source of truth is working code, and the
round trip is mechanically verifiable.

Ask a model to write the caching integration and you get plausible code. Derive
it from a project where caching demonstrably works and you get _that project's_
caching, byte for byte, with a test that proves it. The second one is
falsifiable; the first one is a claim.

### 4. Trust, review surface and cost

A generated project should be auditable by `git diff` — offline, in CI, at zero
marginal cost, with the same result on every machine. A third-party plugin _may_
run code at generation time, if it implements one of the two escape hatches; a
manifest-only plugin (D20) cannot, and a reviewer can tell which is which before
installing either. That distinction is stated plainly rather than implied, and
it is worth keeping sharp — adding non-reproducible output on top of it would
remove the last surface on which a reviewer can say "this is exactly what
changed and why."

### Where AI does belong

Everywhere except between the input and the bytes on disk. Models are good at
authoring a meta project, driving `derive` and confirming what it inferred,
reviewing a plugin before it is published, writing specifications, and —
visibly — much of the work behind this codebase. The boundary is not "no AI."
It is: **whatever the model produces becomes checked-in, reviewed,
deterministic input.** It is never consulted at generation time.

---

## What is built instead

Briefly — the [README](README.md) has the mechanics, and this section keeps to
pointers rather than restating them.

- **Intent versus outcome** — `target.exs` against `plugin.exs`. See **D16**.
- **Plugins are infrastructure, and commutative** — see **G9**, **G10**.
- **Three ownership modes** — sole owner, contributor, seed. See **D6**.
- **Conflicts are commented TODOs, not broken files** — see
  [When a change will not apply](#when-a-change-will-not-apply) and **D7**.
- **One version, bumped by commit type** — `.version` holds one bare `x.y.z`
  line, read by `mix.exs` at compile time.
- **One gate, every commit** — `mix format`, `mix credo --strict`,
  `mix coveralls`, `mix dialyzer` and `mix doctor` run against the same tree,
  so a gate added in one commit reaches every later run.

---

## When a change will not apply

Some hunks will not apply. That is the expected case, not the exceptional one —
any file a developer has edited near where a patch lands will eventually reject
it, and the whole premise of this project is that developers edit generated
files. What Capstone does at that moment is therefore a load-bearing design
decision, not error handling.

Three answers were available. Two of them break the project.

**Abort the run.** Honest, and useless. Generation touches dozens of files; a
run that stops at the first rejection leaves the working tree half-written and
tells the developer to sort it out with no record of what the other twenty files
needed. Rejected outright — that is the mid-write abort G3 forbids.

**Write git-style conflict markers.** `<<<<<<<`, `=======`, `>>>>>>>` are the
obvious reach, and they are wrong here. They leave the file **un-parseable**.
That is acceptable in git, where a human is already stopped mid-merge with
nothing else to do; it is not acceptable from a generator. A broken
`config/config.exs` or `mix.exs` stops the project compiling, and a project that
does not compile has no `mix test`, no `mix format`, no dialyzer and no language
server — which is to say the tool has just removed every instrument the
developer would use to *perform* the merge. **A tool that reports a problem must
not also destroy the means of fixing it.**

**Append the change at the bottom of the file.** The other easy answer, and the
worse one. For `application.ex` the contribution belongs inside a list inside
`start/2`; at the bottom of the file it is outside the module entirely, and the
file no longer parses. Where it *does* happen to parse — a stray tuple after the
last `end` of a `config/*.exs` — it is in the wrong scope and silently does
nothing, which is worse than a syntax error, because a syntax error is at least
reported. Shoving it at the bottom trades a visible failure for an invisible
one.

### What Capstone does instead

The change is written **commented out, at the position it was meant to occupy**,
under a `TODO(capstone)` header that names the plugin, the version transition,
and why placement failed:

```elixir
defmodule MyApp.Application do
  @impl true
  def start(_type, _args) do
    children = [
      MyApp.Repo,
      MyAppWeb.Endpoint
      # TODO(capstone): manual merge required — valkey 1.3.0 → 1.4.0
      #   The `children` list has been edited since it was generated, so this
      #   entry could not be placed automatically. Add it by hand, then delete
      #   this block and re-run `mix capstone.check`.
      #
      #   {Valkey.Supervisor, name: MyApp.Valkey},
    ]
```

The properties that matter:

- **The file still parses.** Comments are inert in every language Capstone writes —
  `.ex`, `.exs`, `.yaml`, `.json` being the exception that needs care — so the
  project compiles, the test suite runs, the formatter runs, and the developer
  has a working toolchain while merging.
- **The change is where it belongs.** A developer reading `start/2` sees the
  pending edit in context, next to the list it was meant to join, rather than
  reconstructing intent from a report describing a file they have to go find.
- **Nothing was overwritten.** Their version of the code is untouched. The
  commented block is purely additive, so the worst case of ignoring it entirely
  is the project they already had.
- **It is a diff, not a mystery.** `git diff` shows an added comment block. A
  reviewer can see exactly what the generator wanted and decide.

### The manual merge is a tracked state, not a hope

A comment nobody reads is a comment nobody acts on, so the TODO is not left to
goodwill:

- **The manifest is not updated for a plugin with an outstanding TODO.** The
  version is recorded only after every hunk actually applied (G5) — so a pending
  manual merge cannot be mistaken later for a completed update, and re-running
  the update re-offers it rather than assuming it was done.
- **`mix credo --strict` fails while a `TODO(capstone)` marker exists.** The gate
  is `Credo.Check.Design.TagTODO`, already in the stack every generated project
  gets, configured with a non-zero `exit_status`. Verified rather than assumed:
  the check does match the parenthesised `TODO(capstone):` form, and a marker
  anywhere in `mix.exs`, `lib/`, `test/` or `config/` takes the run from exit
  0 to exit 2. An incomplete merge is therefore a CI failure, not a comment
  that ages quietly into the codebase. It covers **Elixir sources only** — a
  marker in `compose.yaml` is not seen by Credo and is caught by the report
  instead.
- **The run writes a report** listing every file that took a TODO, with the
  plugin and reason, so the whole set of pending merges is one file rather
  than a hunt.

The developer's loop is therefore: run the update, compile and test (both still
work), read the report, resolve each TODO by hand, delete the block, and re-run
`mix capstone.check` until it exits zero.

---

## Comment-type-based actions

A comment is normally inert — the compiler drops it, and whether anyone acts on
it is a matter of character. Ten comment tags in a Capstone project are not inert.
Four of them fail the build and six do not, which turns a comment from prose
into a **typed signal the toolchain acts on**.

This matters here more than it would elsewhere, because Capstone is itself a writer
of comments. When an update cannot place a change it parks that change in a
`TODO(capstone)` block (previous section). That only works if something downstream
reads the tag back — otherwise the generator has written a note to nobody.

### The vocabulary and what each one does

The ten tags are the defaults of
[`zed-todo-highlight`](https://github.com/shionit/zed-todo-highlight), so the
editor colours them with no per-project configuration, and the colour a
developer sees is the same signal CI acts on.

| Tag          | Colour | Means                                          | Action     |
| ------------ | ------ | ---------------------------------------------- | ---------- |
| `TODO`       | Orange | Work deliberately deferred                     | **blocks** |
| `FIXME`      | Red    | Broken, must be repaired before shipping       | **blocks** |
| `BUG`        | Red    | A defect known, reproduced and still present   | **blocks** |
| `XXX`        | Purple | Code the author already believes is wrong      | **blocks** |
| `HACK`       | Yellow | A deliberate compromise that works             | advisory   |
| `WARN`       | Amber  | A sharp edge for the next reader               | advisory   |
| `WARNING`    | Amber  | As `WARN`                                      | advisory   |
| `NOTE`       | Blue   | Context not obvious from the code              | advisory   |
| `INFO`       | Blue   | As `NOTE`                                      | advisory   |
| `DEPRECATED` | Gray   | Still called, on its way out                   | advisory   |

**The split follows the colours rather than cutting across them.** Red, orange
and purple each mark something the author considers wrong or unfinished, and
shipping one silently is how a known problem becomes an unknown one. Yellow,
amber, blue and gray each mark something the author considers *correct* but
worth saying out loud.

### Why the advisory six must stay advisory

The temptation is to fail on all ten — more enforcement, more rigour. It is the
wrong instinct, and the reason is behavioural rather than technical.

A build that fails on `NOTE` does not produce projects with fewer things worth
noting. It produces developers who stop writing `NOTE`, because the cheapest way
to make the build pass is to delete the comment. The context is still absent
from the code, and now it is absent from the comments too — the enforcement has
destroyed exactly what it was meant to encourage.

So the rule is: **a tag blocks only when the author is telling you something is
wrong.** Tags that record judgement, context or a known compromise must be free
to write, or they will not be written. Enforcement that punishes documentation
yields less documentation, not better code.

### The mechanism, and what it actually does

`mix credo --strict` is the gate. `TODO` and `FIXME` use Credo's built-in
`TagTODO` / `TagFIXME` pinned to `exit_status: 2`; `BUG` and `XXX` have no
built-in and are custom checks loaded via `requires:`. The advisory six are not
merely set to zero — **no check is registered for them at all**, which is what
makes them free.

Measured by planting each tag in a real source file and reading the exit code:

```
BUG  XXX  FIXME  TODO                        -> exit 2
HACK  NOTE  INFO  WARN  WARNING  DEPRECATED  -> exit 0
```

Two limits, both measured rather than assumed:

- **Credo parses Elixir.** A tag in `compose.yaml` is unseen,
  which is why the merge report exists alongside this gate rather than being
  replaced by it.
- **A `#`-prefixed tag inside a `@moduledoc` is not matched** — in a heredoc the
  `#` reads as a markdown heading. Without it the tag matches. Neither shape is
  one the generator writes.

### `TODO(capstone)` is reserved

`TODO(capstone)` means "the generator could not finish this". It is written by the
machine and read by the machine, and a human writing it by hand makes the merge
report claim a pending merge that never existed. The full convention, including
the editor palette, is in `.claude/10-comment-tags.md`.

This is what closes the loop the previous section opened: the tool writes the
tag, the same toolchain reads it back, and CI refuses to go green until a person
has resolved it. G3's "failure is graceful" is only true if the parked state is
also *visible* — otherwise graceful degradation is just a quieter way to lose
the change.

---

## Features

What the finished thing does, stated as capabilities rather than modules. Each
one traces to a decision, and none of them is optional to the goal — this is the
minimum set that makes update possible at all.

| Feature                          | What it means                                                                                                              | From        |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ----------- |
| **Declared intent**              | `target.exs` is hand-authored and answers "what should this project have?". Editing it and regenerating is how a project gains a plugin. | D16        |
| **Recorded outcome**             | `plugin.exs` answers "what was actually applied, at what version?" — every touched path, with an ownership mode and a content hash. | D6, D16    |
| **Composable infrastructure**    | Plugins install caches, container runtimes, vaults, auth stacks, asset pipelines. Never a line of your domain.           | G10         |
| **Order-independent assembly**   | Any permutation of the plugin list yields the same bytes; capability sort decides order, declaration order only breaks ties. | D8, G9   |
| **Derivation from working code** | A plugin is the observed diff between a baseline and a real project that has the feature. `mix capstone.plugin.derive` computes it. | R1, D15 |
| **Deterministic generation**     | Same inputs, same bytes — today and in eighteen months. No timestamps, no randomness, no map iteration order.               | D8, G1      |
| **Three-way update**             | Regenerate the recorded version and the target version, diff those, apply to the working tree.                             | D7, G2      |
| **Graceful conflict**            | A hunk that will not apply is written in place as a commented `TODO(capstone)` block and recorded in the report. The run continues, and the file still compiles. | D7, G3 |
| **Non-Elixir files first class** | `compose.yaml`, `package.json`, assets, dotfiles — written through our own writer and hashed identically to `.ex` files.    | D11         |
| **Drift check**                  | `mix capstone.check` exits non-zero while any unresolved manual-merge region remains — usable as a CI gate. Comparing intent, manifest and working tree three ways is not yet built. | G8          |
| **Third-party plugins**       | A plugin from a separate repository installs without editing Capstone's source, via declared capabilities — as a module, or as a manifest that cannot run at all. | R4, D13, D20, G7 |
| **Nothing is evaluated**         | `target.exs` and `plugin.exs` are parsed as literals. Reading a project's configuration never runs its code.               | G6          |

---

## The failure modes it exists to prevent

Capstone supersedes earlier attempts. Failure modes were named from them, and
each one has a structural answer rather than a resolution to be more careful
next time.

| ID     | Failure                                                                                                                                                                                 | Why it cannot repeat                                                                                                                                                                       |
| ------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **F2** | Option files were **inline** inside large documents. No per-file version control, nothing to diff, nothing to hash.                                                                     | **D6/D11** — a plugin is files on disk, every one of them recorded in `plugin.exs` with an ownership mode and a content hash, Elixir and non-Elixir alike.                            |
| **F3** | Option documents were too large; agents lost context; output was LLM-improvised and broke easily. Two projects generated from one document were not the same project.                   | **D8** and derivation — a plugin is the observed diff from a working baseline, and `test/capstone/plugin/{derive,round_trip}_test.exs` assert `derive` still reproduces the checked-in plugin, on every CI run. No model in the execution path.       |
| **F4** | The scaffolder's own `mix.exs` competed with the generated project's, and **some tests silently did not run**.                                                                          | **D4** — the generated project is always the resolution target; `app_name/0`, `module_name_prefix/0` and direct `Mix.Project.*` are banned, and test invariants assert the resolved target. |

F4 is worth stating twice, because its symptom is silence. Anything that
narrows what the suite covers — an excluded tag, a skipped output, a gate
that did not run — has to announce itself in the run, or it is F4 wearing a
different hat.

---

## Failures encountered

The failure modes above are inherited from earlier attempts. The list below is
different: concrete failures hit while researching and standing this up, each one
reproduced rather than reasoned about. They are recorded because every one of
them was invisible until it was measured, and because most of them are still
live hazards for anyone touching the same surfaces.

| ID      | What happened                                                                                                                                                     | Where it bit                                                                          |
| ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| **E1**  | Prefix matching on raw atom text rewrote code the tool never owned: `:auth` turned `:authorized` into `:tgtorized`, `AuthHelper.Thing` into `TgtHelper.Thing`.    | Fireside 0.2.0 — and invisible to its own integrity check, because unmanaged files are never hashed. |
| **E2**  | A module vendored into a Mix archive **permanently** shadows the project's real one. Touch the archive's `Jason` once and every later call in the VM gets it.      | Killed "vendor the deps into the archive" outright, and made `Code.ensure_loaded?/1` useless as a capability probe. |
| **E3**  | `Mix.Project.compile_path()` re-expanded a relative `build_path` against a changed cwd, the module index silently degraded to empty inside a bare `rescue`, and lookup fell back to globbing. | A reproduced mechanism for F4 — no error, no warning, different behaviour in the scaffolder than in a normal project. |
| **E4**  | Hashing rendered AST is comment-sensitive: one added `# note` produced "diverged, aborting" forever.                                                              | A `# credo:disable-for-next-line` would have locked a project out of updates permanently. |
| **E5**  | `mix archive.build` silently drops dotfiles under `priv/` unless `--include-dot-files`, and `archive.install hex` passes no options.                              | Ship `gitignore.eex`, never `.gitignore`.                                                |
| **E6**  | `tty?/0` reads **STDIN** and assumes a TTY on error, so `< /dev/null` in CI is classified as interactive — the task prompts and then crashes on EOF.              | Not a wrong default but a crash. Hence D12: always pass `--yes`.                          |
| **E7**  | Transform exceptions were swallowed by a bare `rescue` and **the version was bumped anyway**.                                                                     | Fireside 0.2.0 — the manifest became a claim rather than a fact. G5 exists because of this. |
| **E8**  | lefthook defaults `skip_empty: true` and derives a file list for pre-push hooks. A push that moves only refs yields an empty list, so every command prints "(skip)" and none run. | The `protect-master` guard was inert for precisely the push it exists to police. Fixed by `skip_empty: false` on every command. |
| **E9**  | Branch protection required checks named `test`, `lint` and `build` — strings this repository has never emitted. A required check that never reports does not fail; it sits pending. | Every PR permanently unmergeable, with nothing on screen explaining why.                   |
| **E10** | `LEFTHOOK=0` to get past one guard skips `mix test` as well.                                                                                                      | A bypass intended to be narrow silently drops the whole pre-push suite.                   |
| **E11** | Two stray archives installed on the development machine polluted every `mix` invocation that did not reach `compile.all`.                                          | Diagnosed only after unexplained behaviour; `mix archive.uninstall` was the fix.          |

The pattern worth naming: **nine of these eleven fail silently.** Not one
announced itself — they were found by measuring, by probing with a deliberate
canary, or by noticing that something which should have run left no trace. That
is the same shape as F4, and it is why the goals in this document are phrased as
assertions in CI rather than as intentions.

---

## Decisions

The decisions below are the load-bearing ones. Each was reproduced against real
packages rather than read from documentation.

| ID      | Decision                                                                                                                                                                                       | Because                                                                                                                                                       |
| ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **D1**  | **Reimplement, do not depend on Fireside.** Keep the manifest format; write everything between reading the manifest and writing it back. No Fireside code is copied in.                        | Fourteen reproduced defects against 0.2.0, one of which silently corrupts code Fireside does not own. Owning the format is cheap; owning the implementation is not. |
| **D4**  | **The generated project is always the resolution target.** Ban `app_name/0`, `module_name_prefix/0` and direct `Mix.Project.*`; re-establish the Mix project before any patching work.         | F4, with a precise mechanism: a relative `build_path` re-expands under a changed cwd, the module index degrades to empty inside a bare `rescue`, and nothing warns. |
| **D5**  | Plugin **versions are semver strings**, not integers.                                                                                                                                       | An integer scheme cannot bridge to anything that expects semver, and it forecloses delegating upgrades later.                                                  |
| **D6**  | The manifest records **per-file ownership mode** — `:sole_owner`, `:contributes`, `:seed`. Contributions to shared files carry idempotency keys.                                               | `router.ex`, `application.ex`, `config/*.exs`, `mix.exs`, `package.json` and `compose.yaml` all receive contributions from the base **and** from every feature.  |
| **D7**  | Update is a **cruft-style three-way merge**: regenerate the recorded version and the target version, diff _those_, apply to the working tree, fall back to a commented TODO in place.                   | The only mechanism that survives hand-edited files. There is no merge, no conflict marker and no `.rej` anywhere else in the ecosystem.                        |
| **D8**  | **Generation is deterministic** — same inputs, same bytes. No timestamps, no randomness, no map iteration order in output.                                                                     | D7 is impossible without it: the merge regenerates a historical baseline and diffs it. Also the answer to F3.                                                  |
| **D9**  | Identity rewriting is **scoped to the plugin's own files** and matches on **segment boundaries**, never prefix matching on raw atom text.                                                   | The disqualifying defect: `:auth` turning `:authorized` into `:tgtorized` in files the tool has never owned and will never hash.                               |
| **D10** | Plugins declare target-facing dependencies in a **manifest field**, never by reflecting their own `mix.exs`.                                                                                | Reflection copies path deps and environment-specific settings straight into the target and breaks it — F4 again, by another route.                             |
| **D11** | **Non-Elixir files are first class**, written through our own writer and tracked identically to Elixir files.                                                                                  | The option set — docker, podman, valkey, `live_svelte` assets — is dominated by files no AST-based importer can handle at all.                                 |
| **D12** | **Never rely on interactive prompts.** Always pass `--yes`; surface review as a diff artifact and a `--check` gate.                                                                            | CI stdin classification is not controllable, and the failure is a crash on EOF rather than a sensible default.                                                 |
| **D13** | Plugins are distributed as **hex packages, not archives**.                                                                                                                                  | An archive carries no dependencies of its own and, once installed, its modules permanently shadow a project's real ones — the same evidence as E2.             |
| **D15** | **One meta project per feature, plus a conditional.** Base variance is declared inside the plugin, not by duplicating the meta project.                                                     | A projection onto the other base is a _subset_ of a single observed diff, never a second hand-maintained one. CI must assert the unobserved projection builds. |
| **D16** | **Two files.** `target.exs` is hand-authored intent; `plugin.exs` is generated lock.                                                                                                       | One file cannot be both hand-edited and safely regenerated, and the update flow must compare what was asked for against what was applied.                      |
| **D17** | **MVP scope is `base_otp_app` and `base_web_app` only.** No feature plugins ship in the MVP.                                                                                                | Two mutually exclusive bases depend on nothing, so the capability solver has no constraint graph to solve yet. The contract fields are still specified now.    |
| **D18** | The existing config expander is **reused or discarded** when its consumer is written, not before.                                                                                              | Not a blocker either way, and deciding it early would be deciding it without evidence.                                                                         |
| **D19** | **A plugin is a module implementing the `Capstone.Plugin.Behavior` behaviour; the project's `plugin.exs` lock stays pure data.** Six callbacks return static declarations; only `transform/2` and `upgrade/3` are code, and both are optional. | R4 needs a contract that is public and checkable on day one: a malformed plugin must fail when it is *built*, not when someone else's project tries to install it. `plugin.exs` cannot take the same treatment — the update task must read it from a project that does not compile, so it is parsed as a literal and never evaluated (G6). |
| **D20** | **A plugin that needs no escape hatch may be declared as a manifest alone, with no module.** `priv/plugin/manifest.exs` carries the same six declarations the behaviour's data callbacks return, parsed as a literal and never evaluated. The `Capstone.Plugin.Behavior` behaviour remains the path for a plugin that genuinely needs `transform/2` or `upgrade/3`. | D19 forced every plugin to be code, which over-charged the common case: most plugins are a file list, a dep list and a capability set, and none of that needs to run. A manifest-only plugin is inspectable before installation and cannot execute at generation time at all — which turns "third-party plugins run arbitrary code" from a blanket property into a per-plugin one a reviewer can check. |

### What D20 costs

Allowing two declaration forms is not free, and both costs land on the loader
rather than on the plugin author:

- **It trades compile-time validation for inspectability.** D19's best property
  is that a malformed plugin fails when it is *built* — a missing name, a
  non-semver version, caught by `use Capstone.Plugin.Behavior` before the package is ever
  published. A manifest has no build step, so those checks move to load time,
  and a broken manifest-only plugin is found by the first project that installs
  it. The loader must therefore validate a manifest at least as strictly as the
  macro validates its options, and fail in the same terms.
- **Two forms must collapse into one shape.** Resolution, ordering and the
  update flow must never branch on how a plugin was declared. The loader
  normalises both into a single struct at the boundary, or every consumer
  downstream pays for the choice again.

---

## Numbered goals

The goal is met when all of these hold, and each is a test rather than an
aspiration:

| ID     | Goal                                 | Met when                                                                                                                                                          |
| ------ | ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **G1** | **Determinism**                      | The same inputs produce byte-identical output, asserted in CI, including under a reversed atom-interning order.                                                   |
| **G2** | **Edits survive**                    | A file a developer hand-edited still carries that edit after an update that also changed it.                                                                     |
| **G3** | **Failure is graceful**              | A hunk that will not apply produces a commented TODO in place and a report; the file still parses and the project still compiles. Never a mid-write abort, never a silent overwrite. |
| **G4** | **Derivation is lossless**           | Rendering a plugin composed onto a base reproduces the working project it was derived from.                                                                    |
| **G5** | **The manifest is a fact**           | A version is recorded only after every step succeeded; a failed transform never bumps a version.                                                                 |
| **G6** | **Nothing runs that you didn't read** | `target.exs` and `plugin.exs` are parsed as literals and never evaluated.                                                                                       |
| **G7** | **Third parties are first class**    | A plugin from a separate repository installs without editing Capstone's source.                                                                                   |
| **G8** | **Generated projects are real**      | Both bases compile and pass their own tests, and a freshly generated project reports no drift.                                                                   |
| **G9** | **Composition is order-independent** | Permuting the plugin list produces byte-identical output; adding a plugin to an existing project matches generating it with that plugin from the start. |
| **G10** | **Plugins are domain-free**      | No plugin reads, names or generates domain code. Two projects differing only in enabled plugins differ only in infrastructure.                              |

G1 is the one the others rest on: without it there is no three-way merge, so G2
and G3 have nothing to stand on and G4 has nothing to compare against. G9 is the
one that makes the whole thing usable rather than merely correct — a scaffolder
whose plugins must be added in a fixed order is a scaffolder you can only run
once, which is the day-two problem again under a different name.

---

## Opportunities

Things the architecture makes cheap that were not the reason for building it.
None is committed work; they are recorded so the shape of the design is not
mistaken for the limit of it.

- **`derive` generalises past our own plugins.** Any working project that
  differs from a baseline by one feature can become a plugin. The tool that
  builds Capstone's own catalogue is also the tool a team uses to capture *their*
  house conventions once and replay them onto every project they own.
- **Meta projects are integration tests for the ecosystem.** Each one is a real
  project that compiles and passes its own tests with a real library wired in.
  Running them on a schedule detects an upstream breaking change before a
  generated project does.
- **A fleet-wide drift gate.** `mix capstone.check` in a scheduled CI job across
  every project a team owns answers "which of our forty services are behind, and
  on what?" — a question nobody can currently ask of a scaffolder.
- **Semver keeps the Igniter door open.** D5 chose semver over Fireside's
  integers specifically so upgrade orchestration could later be delegated rather
  than owned, if owning it stops paying.
- **Order-independence buys more than correctness.** If composition is
  commutative, rendered plugins can be cached and composed in parallel, and a
  plugin can be added to or removed from a project without replaying the rest.
- **Offline, deterministic, `git diff`-auditable output travels well.** A
  generator whose entire behaviour is reproducible on an air-gapped machine is
  an easier sell in a regulated environment than one that calls out to anything.
- **AI at authoring time is real leverage.** Models are good at drafting a meta
  project, driving `derive` and confirming what it inferred, and reviewing a
  plugin before publication. That is a large productivity surface that costs
  nothing at the boundary this document defends, because whatever a model
  produces becomes checked-in, reviewed, deterministic input.

---

## Potential pitfalls

Where this is most likely to go wrong. Stated plainly, because a risk written
down is one someone can test for.

**Designed but unproven.** Three load-bearing mechanisms have no exercise yet:

- **`:contributes` idempotency keys.** Two bases never contribute to the same
  file, so the ownership mode that exists *specifically* for the many-contributor
  case will not be validated until a second plugin exists. It is specified and
  unproven — the single largest gap between this design and a working one.
- **The three-way merge.** Inherited as a pattern from cruft; not prototyped
  here. G2 and G3 both rest on it.
- **The capability solver.** Designed, deferred by D17, and unvalidated. Two
  mutually exclusive bases produce no constraint graph to solve.

**Determinism decays quietly.** Nothing about the BEAM makes byte-identical
output the default. Map iteration order, `File.ls/1` ordering, a timestamp in a
header comment, atom interning — each is one careless line, and the failure is
not a crash but a merge that silently produces the wrong patch six months later.
G1's CI assertion is the only thing standing between the design and that, which
means the assertion itself is load-bearing infrastructure, not a nicety.

**Order-independence is an assertion, not a property.** G9 holds only as long as
something permutes the plugin list and compares bytes. Without that test it
will decay the first time a plugin reads state another plugin wrote.

**Formats without comments break the in-place guarantee.** The commented-TODO
answer assumes the file has a comment syntax. `package.json` does not. For JSON —
and any other comment-less format a plugin contributes to — the change cannot
be parked in place, so it falls back to the report and a sidecar file. That is
the one class of file where "the project still compiles and the pending edit is
where it belongs" does not both hold, and it needs a decision of its own before
the first plugin that touches `package.json` ships.

**A TODO can still rot.** Parking a merge in a comment only works while something
insists on it. `Credo.Check.Design.TagTODO` with a non-zero `exit_status` is that
something — but it is one line in a generated project's `.credo.exs`, and the
project owns that file. A team that sets `exit_status: 0` after one noisy update,
or drops credo from CI, is left with a block that ages into the codebase and is
eventually read as intentional. The mechanism is sound; its enforcement lives in
a file we hand over on day one.

**Comment-stripped hashes cut both ways.** E4's fix — treat comments as
user-owned — means a comment-only change to a generated file is invisible to
drift detection. That is the intended trade, but it does mean the manifest
cannot claim byte-level fidelity, only semantic fidelity.

**The unobserved projection.** D15 accepts that a plugin derived on the `:web`
base has an `:otp` projection nobody ever directly observed. Without the CI
assertion that the projection still compiles and passes tests, D15 has traded a
maintenance cost for a silent-breakage cost — which is exactly the trade F3
warns against.

**Vendoring is ownership.** Not of Fireside — none of its code is here; D1 kept
the manifest format and reimplemented the rest. The cost landed elsewhere:
`lib/capstone/vendor/` carries four upstream trees (sourceror, vex,
typedstruct, simple_enum), bugs included, with no upstream to inherit fixes
from while they stay pinned. Cheaper than constraining every consuming
project's resolution, but not free, and the cost arrives later than the
saving.

**The chain from generation to a running release is checked only by hand.**
Everything above is verified up to the point a project compiles and passes its
own tests. Nobody has yet wired an end-to-end check that generates a project,
resolves its dependencies for real, applies a plugin, builds a release and
confirms the deployed thing answers a request — and that gap is exactly where
`phx.gen.release --docker` output shape, executable-file modes on plugin
files, and similar surprises live undiscovered until someone runs the whole
thing by hand. The general lesson: the parts of this tool that are checked by
running it are the parts that turn out to be wrong in ways nobody predicted,
and the parts checked only by reading stay merely plausible.

**Line coverage never speaks to any of this and must not be read as if it
did.** A 100% line-coverage gate is satisfied entirely by in-process tests; it
says nothing about whether generation-to-deployment actually works. It is the
tagged, deliberately-run integration test — not the percentage — that says the
thing works.

---

## Non-goals

- **Not an application builder.** Capstone scaffolds and maintains structure. It
  does not write your domain.
- **Not a general code-mod framework.** Igniter is the right tool for that, and
  is credited as such. Capstone solves a deliberately narrower problem.
- **No model in the execution path.** Not now, and not as an opt-in flag — an
  optional non-deterministic path is still a non-deterministic path, and it
  would take the update model down with it.
