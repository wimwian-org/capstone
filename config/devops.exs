import Config

# Standard dev/master promotion model -- same as Devops.Config's own
# defaults, spelled out explicitly here rather than left implicit.
# Devops.Commit.ff/1 fast-forwards "dev" onto a feature branch, then
# "master" onto "dev" -- both branches need to exist locally (and,
# once a remote is configured, on it) for that to succeed.
config :devops, :branches,
  integration: "dev",
  production: "master",
  default: "dev",
  remote: "origin",
  tag_prefix: "v"

# Devops.Commit.local/1's preflight and message-generation seams.
# `tools` are checked on PATH before anything is staged (in addition to
# whatever `commit_message`'s own `requires_tools/0` adds -- see
# Devops.CommitMessage.AI, which adds nothing itself since it degrades
# gracefully to Devops.CommitMessage.Manual). `commit_message` and
# `ai_backend` are each independently pluggable behaviours -- see
# Devops.CommitMessage and Devops.AI.
config :devops, :prehook,
  tools: ["git", "mix"],
  commit_message: Devops.CommitMessage.AI,
  ai_backend: Devops.AI.ClaudeCLI

# Devops.GitFlow.await_checks/2's poll bound and tick, in milliseconds.
config :devops, :ci,
  await_timeout_ms: 600_000,
  poll_interval_ms: 15_000

# Devops.Version.bump/4's type -> effect table, spelled out explicitly
# here rather than left implicit, same as :branches above -- these entries
# are exactly Devops.Config's own shipped defaults, covering every
# Conventional Commit type Devops.CommitValidate/Devops.CommitMessage
# accept. A type not listed here still falls back to :patch. A breaking
# marker (`!` or a `BREAKING CHANGE` footer) escalates one level once
# major >= 1: :minor to :major, :patch to :minor -- :none is never
# escalated, so a chore commit never moves the version even when marked
# breaking.
config :devops, :commit_types,
  feat: :minor,
  perf: :minor,
  revert: :minor,
  fix: :patch,
  docs: :patch,
  refactor: :patch,
  style: :patch,
  test: :none,
  chore: :none,
  build: :none,
  ci: :none

default_ci_gates = %{
  "format" => {~w(format --check-formatted), :root},
  "credo" => {~w(credo --strict), :root},
  "tests + 100% coverage" => {~w(coveralls), :root},
  "dialyzer" => {~w(dialyzer), :root},
  "doctor" => {~w(doctor), :root}
}

current_ci_gates = Map.merge(default_ci_gates, %{})

config :devops, :gates, current_ci_gates

# Devops.Gates.resolve/1's own filter over the gate list above -- every
# gate currently resolved (via :gates, above) listed explicitly and
# enabled, since Devops.Gates.resolve/1 raises on a :quality key that
# does not match a resolved gate: this map must stay in sync with
# `default_ci_gates` above whenever a gate is added, removed, or
# renamed here.
config :devops, :quality, %{
  "format" => true,
  "credo" => true,
  "tests + 100% coverage" => true,
  "dialyzer" => true,
  "doctor" => true
}

# Whether Devops.Commit.local/1 calls Devops.Version.bump!/1 (and
# rebuilds) after committing. `.version` at the project root is what
# gets bumped -- mix.exs reads it back via @version, so the two never
# drift.
config :devops, :posthook, bump_version: true

# Read only by Devops.Init.run/1, to create the wimwian-org/devops
# GitHub remote this repo already has as `origin`.
config :devops, :repo,
  scs: :github,
  owner: "wimwian-org",
  name: "capstone",
  visibility: :private
