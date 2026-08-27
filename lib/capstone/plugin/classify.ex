defmodule Capstone.Plugin.Classify do
  @moduledoc """
  Decides what a hunk means (SDD 7.3).

  A hunk is APPENDABLE — `:contributes` — only if it both parses as standalone
  Elixir and begins at column 0. Parsing alone is not enough: `import Foo` and
  `alias Foo` parse perfectly well but must live inside a module, and appending
  either to the end of a file produces code that does not compile.

  Everything else is `:manual`: shipped verbatim and applied as conflict
  markers, because there is no safe automatic placement for an insertion inside
  an existing expression.
  """

  @elixir_extensions ~w(.ex .exs)

  @doc """
  The bucket for a hunk of added lines.

  `path` selects the test: only Elixir source can be parsed, so every other
  extension defaults to `:contributes`, matching 7.1's `compose.yaml` and
  `assets/js/app.js` entries.
  """
  @spec bucket([binary()], Path.t()) :: :contributes | :manual
  def bucket(lines, path) do
    cond do
      Path.extname(path) not in @elixir_extensions -> :contributes
      appendable?(lines) -> :contributes
      true -> :manual
    end
  end

  @doc """
  An idempotency key for a keyed entry, unique within the plugin.

  `taken` is the keys already assigned; a collision gets a numeric suffix.
  """
  @spec key(atom(), Path.t(), [atom()]) :: atom()
  def key(plugin, path, taken) do
    # Downcased: README.md would otherwise yield :cache_README.
    stem = path |> Path.basename() |> Path.rootname() |> Path.rootname() |> String.downcase()
    base = :"#{plugin}_#{stem}"

    if base in taken, do: unique(base, taken, 2), else: base
  end

  defp unique(base, taken, n) do
    candidate = :"#{base}_#{n}"

    if candidate in taken, do: unique(base, taken, n + 1), else: candidate
  end

  defp appendable?(lines) do
    significant = Enum.reject(lines, &(String.trim(&1) == ""))

    significant != [] and top_level?(significant) and parses?(significant)
  end

  defp top_level?([first | _rest]), do: first == String.trim_leading(first)

  defp parses?(lines) do
    case lines |> Enum.join("\n") |> Code.string_to_quoted() do
      {:ok, _ast} -> true
      {:error, _reason} -> false
    end
  end
end
