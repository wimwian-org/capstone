defmodule Mix.Tasks.Capstone.Check do
  @shortdoc "Fails while any unresolved manual region remains"
  @moduledoc """
  Fails while any unresolved `:manual` region remains.

      mix capstone.check [dir]

  D12 forbids resolving a conflict with a prompt, so apply writes a marked
  region and this task is the gate that keeps it from being forgotten.

  Meant to run inside a GENERATED project. Pointed at this repository it
  reports the example markers in `docs/`, which are documentation rather than
  unresolved work.
  """
  use Mix.Task

  alias Capstone.Plugin.Apply
  alias Capstone.VersionGuard

  # `.elixir_ls` and `.expert` join the list because the walk otherwise reads
  # thousands of .beam files out of a language server's own build directory --
  # not a correctness bug, but seconds of I/O for a directory that can hold no
  # marker.
  @pruned ~w(.git deps _build .elixir_ls .expert)

  @impl Mix.Task
  def run(argv) do
    VersionGuard.verify!()
    dir = List.first(argv, ".")

    found =
      dir
      |> Path.join("**")
      |> Path.wildcard(match_dot: true)
      |> Enum.reject(&(File.dir?(&1) or pruned?(&1)))
      |> Enum.flat_map(&markers/1)

    case found do
      [] -> Mix.shell().info("capstone.check: no unresolved manual regions")
      hits -> Mix.raise("unresolved manual regions:\n\n  " <> Enum.join(hits, "\n  "))
    end
  end

  defp pruned?(path), do: path |> Path.split() |> Enum.any?(&(&1 in @pruned))

  defp markers(file) do
    contents = File.read!(file)

    if String.valid?(contents) and String.contains?(contents, Apply.marker_prefix("")) do
      ~r/#{Regex.escape(Apply.marker_prefix(""))}(\S+)/
      |> Regex.scan(contents)
      |> Enum.map(fn [_full, key] -> "#{file}: #{key}" end)
    else
      []
    end
  end
end
