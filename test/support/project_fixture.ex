defmodule Capstone.ProjectFixture do
  @moduledoc """
  Creates throwaway project directories, including ones that deliberately do
  not compile. SDD step 4's acceptance criterion is "round-trips against a
  project that does not compile", so producing such a project is
  infrastructure, not test detail.
  """

  @valid ~s|defmodule Fixture.MixProject do\n  use Mix.Project\n  def project, do: [app: :fixture, version: "0.1.0"]\nend\n|
  @broken_syntax ~s|defmodule Fixture.MixProject do\n  use Mix.Project\n  def project, do: [app: :fixture\nend\n|
  @broken_semantics ~s|defmodule Fixture.MixProject do\n  use Mix.Project\n  Nonexistent.Module.call!()\n  def project, do: [app: :fixture, version: "0.1.0"]\nend\n|

  @doc "Creates `dir` and writes a `mix.exs` of the requested variety."
  @spec create!(Path.t(), :valid | :broken_syntax | :broken_semantics | :no_mix_exs) :: Path.t()
  def create!(dir, variety) do
    File.mkdir_p!(dir)
    write_mix_exs!(dir, variety)
    Path.expand(dir)
  end

  defp write_mix_exs!(_dir, :no_mix_exs), do: :ok
  defp write_mix_exs!(dir, :valid), do: File.write!(Path.join(dir, "mix.exs"), @valid)

  defp write_mix_exs!(dir, :broken_syntax),
    do: File.write!(Path.join(dir, "mix.exs"), @broken_syntax)

  defp write_mix_exs!(dir, :broken_semantics),
    do: File.write!(Path.join(dir, "mix.exs"), @broken_semantics)
end
