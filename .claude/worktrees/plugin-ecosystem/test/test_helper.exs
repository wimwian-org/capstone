# `credo/checks/` is outside every `elixirc_paths` on purpose, so the custom
# checks never reach a compiled application -- `CredoCommentTagsTest` asserts
# that. `CredoNoRuntimeDepsTest` still has to call one, so its source is
# required here: that loads the module into the VM without writing a BEAM into
# `_build/*/lib/capstone/ebin`.
Code.require_file(Path.join([File.cwd!(), "credo", "checks", "no_runtime_deps.ex"]))

# ex_machina and faker are runtime: false, so they are not auto-started.
{:ok, _} = Application.ensure_all_started(:ex_machina)
{:ok, _} = Application.ensure_all_started(:faker)

# Tags this suite excludes by default, and what each one costs:
#
#   :credo_tags  shells out to a real `mix credo --strict` eleven times and is
#                the bulk of a `--include credo_tags` run's wall clock, failing
#                intermittently for a cause nobody has pinned down
#   :toolchain   needs `mix new` / `mix phx.new` on the machine
#   :determinism re-runs a subprocess probe under a reversed atom-interning order
#   :e2e         the whole chain -- network, a podman machine, minutes not seconds
#
# They are excluded rather than merely slow-tagged because a machine without the
# generators reports them as failures rather than as absences, and a red suite
# that says nothing about the code under test is how a suite gets ignored.
ExUnit.start(exclude: [:credo_tags, :toolchain, :determinism, :e2e])
