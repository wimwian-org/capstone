defmodule Mix.Tasks.Capstone.Baseline.Record do
  @shortdoc "Rewrites priv/baselines.exs and emits the content-addressed snapshot"
  @moduledoc """
  Rewrites `priv/baselines.exs` and emits the content-addressed snapshot.

  Recomputes only `files` and `tree_digest`; `generator_version` and every other
  human-owned field is preserved. Run this after regenerating a baseline tree,
  then attach the archives to the release:

      mix capstone.baseline.record
      gh release upload v<version> *_<version>_*.tar.gz

  Each archive is named `<type>_<version>_<last 8 of sha>.tar.gz` — the manifest
  key, this project's version, and enough digest to distinguish. The version in
  the name is the one the release tag carries, so the glob above selects exactly
  the archives this run produced and leaves an earlier release's behind.
  """
  use Mix.Task

  alias Capstone.Baseline
  alias Capstone.Source
  alias Capstone.VersionGuard

  @manifest "priv/baselines.exs"

  # Read here rather than taken from the build's project config: that is ambient
  # state and `Capstone.BoundaryGuard` bans the call outright under `lib/`. `.version`
  # is the source of truth anyway -- `mix.exs` reads this same file rather than
  # storing a literal -- so this is the shorter path to it, not a second copy.
  # Read at RUN time, because the `post-commit` hook bumps `.version` after the
  # build that is running has already been compiled.
  @version_file ".version"

  # `@recursive true` is what makes this task work at the umbrella root.
  # Measured: a plain Mix task run there gets the ROOT's cwd, so a bare
  # "priv/baselines.exs" resolves to capstone_umbrella/priv/baselines.exs, which
  # does not exist -- and the task reports finding nothing rather than failing.
  # Recursive, it runs once per app with each app's directory as cwd, which is
  # where the payload actually is.
  #
  # That also means it runs in apps/capstone_new, which has no payload at all,
  # so a missing manifest is a NO-OP rather than a raise: `mix
  # capstone.baseline.record` typed at the root does the right thing in the one
  # app that has a priv/baselines.exs and nothing in the rest.
  @recursive true

  @impl Mix.Task
  def run(_argv) do
    VersionGuard.verify!()
    if File.regular?(@manifest), do: record(), else: :ok
  end

  defp record do
    manifest = @manifest |> Baseline.read!() |> Baseline.record()
    File.write!(@manifest, Source.encode!(manifest))
    Mix.shell().info("wrote #{@manifest}")

    version = @version_file |> File.read!() |> String.trim()

    for {key, entry} <- Enum.sort(manifest), do: write_snapshot(key, entry, version)
  end

  # One archive per baseline project, each independent: a change to the web
  # baseline must not move the grpc archive's sha.
  #
  # No sidecar file. `archive_sha256` is already recorded in the manifest, and
  # the pin below asserts the bytes written match what was recorded there.
  defp write_snapshot(key, entry, version) do
    {sha, gzipped} = Baseline.snapshot(entry)
    ^sha = entry.archive_sha256
    archive = Baseline.archive_name(key, version, sha)

    File.write!(archive, gzipped)

    Mix.shell().info("#{key}: #{map_size(entry.files)} files -> #{archive}")
  end
end
