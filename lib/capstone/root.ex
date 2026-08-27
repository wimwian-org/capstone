defmodule Capstone.Root do
  @moduledoc """
  A validated, absolute path to the project Capstone is acting on.

  This module exists because of failure F4. `Mix.Project`'s `compile_path/0`
  and `build_path/0` re-expand a relative `_build` against the current working
  directory on *every* call, so once the process changes directory they return
  a path that does not exist — while `Mix.Project`'s `get!/0` keeps reporting
  the scaffolder. The leak is asymmetric, nothing raises, and that is why it
  hid.

  A `%Root{}` captures the root once, absolutely, so no code in `lib/` ever
  asks Mix or the cwd which project it means.

  The prose above is deliberately written without the literal tokens
  `Capstone.BoundaryGuard` bans: the guard is a substring scan over the whole
  file, comments and docs included, so naming the hazard the obvious way would
  make `lib/` fail its own boundary test.
  """

  @enforce_keys [:root]
  defstruct [:root]

  @type t :: %__MODULE__{root: Path.t()}

  @doc """
  Builds a target from a path to a directory containing a `mix.exs`.

  The `mix.exs` is never parsed or compiled — only its existence is checked —
  so this succeeds against a project that cannot build.
  """
  @spec new!(Path.t()) :: t()
  def new!(root) do
    expanded = Path.expand(root)
    validate_directory!(expanded)
    validate_mix_exs!(expanded)
    %__MODULE__{root: expanded}
  end

  @doc """
  Resolves a project-relative path against the target root.

  Raises `Capstone.Root.EscapeError` if the result would fall outside the
  root, including for absolute inputs.
  """
  @spec path(t(), Path.t()) :: Path.t()
  def path(%__MODULE__{root: root}, relative) do
    validate_relative!(relative, root)
    joined = Path.expand(Path.join(root, relative))
    validate_contained!(joined, root)
    joined
  end

  defp validate_directory!(path) do
    if File.dir?(path) do
      :ok
    else
      raise __MODULE__.InvalidRootError, message: "not a directory: #{path}"
    end
  end

  defp validate_mix_exs!(path) do
    if File.regular?(Path.join(path, "mix.exs")) do
      :ok
    else
      raise __MODULE__.InvalidRootError, message: "no mix.exs in: #{path}"
    end
  end

  defp validate_relative!(relative, root) do
    if Path.type(relative) == :relative do
      :ok
    else
      raise __MODULE__.EscapeError, message: "#{relative} is not relative to #{root}"
    end
  end

  defp validate_contained!(joined, root) do
    if joined == root or String.starts_with?(joined, root <> "/") do
      :ok
    else
      raise __MODULE__.EscapeError, message: "#{joined} escapes #{root}"
    end
  end
end

defmodule Capstone.Root.InvalidRootError do
  @moduledoc "Raised when a path is not a usable project root."
  defexception [:message]
end

defmodule Capstone.Root.EscapeError do
  @moduledoc "Raised when a project-relative path would escape the target root."
  defexception [:message]
end
