defmodule Capstone.Plugin do
  @moduledoc """
  Reads and writes `manifest.exs` — a plugin's manifest (SDD 7.1).

  Plain data: no module definition, and nothing that loads the manifest by
  requiring it as source — the `MatchError` trap 7.1 calls out in Fireside.
  `Capstone.Source` is the only reader, so a manifest that tries to execute code
  fails to decode rather than running.

  Like `Capstone.Manifest`, this prose avoids the literal tokens
  `Capstone.BoundaryGuard` bans: the guard is a substring scan over the whole
  file, docs included, so naming those loaders the obvious way would make
  `lib/` fail its own boundary test.
  """

  alias Capstone.Source

  @doc "Reads a plugin manifest."
  @spec read!(Path.t()) :: map()
  def read!(path), do: Source.decode!(File.read!(path), path)

  @doc """
  Writes a plugin manifest as deterministic bytes.

  Byte stability is required by D8 so CI can assert that re-deriving reproduces
  the checked-in plugin.
  """
  @spec write!(Path.t(), map()) :: :ok
  def write!(path, plugin) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Source.encode!(plugin))
  end
end
