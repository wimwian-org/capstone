defmodule Mix.Tasks.Capstone.Gen.Config do
  @shortdoc "Writes a starter target.exs"
  @moduledoc """
  Writes a starter `target.exs`.

      mix capstone.gen.config [--path PATH] [--force]

  `PATH` defaults to `target.exs` in the current directory. Refuses to
  overwrite an existing file unless `--force` is given.
  """

  use Mix.Task

  @switches [path: :string, force: :boolean]

  @scaffold """
  %{
    schema_version: 1,
    base: :api,
    project: [name: "my_app", github_org: "acme"],
    plugins: []
  }
  """

  @impl Mix.Task
  def run(argv) do
    {opts, positional, invalid} = OptionParser.parse(argv, strict: @switches)
    reject_invalid!(invalid)
    reject_positional!(positional)

    path = Keyword.get(opts, :path, "target.exs")
    force? = Keyword.get(opts, :force, false)

    if File.exists?(path) and not force? do
      Mix.raise("#{path} already exists; pass --force to overwrite")
    end

    File.write!(path, @scaffold)
    Mix.shell().info("wrote #{path}")
  end

  defp reject_invalid!([]), do: :ok

  defp reject_invalid!(invalid) do
    Mix.raise("unknown switch: #{inspect(Enum.map(invalid, &elem(&1, 0)))}")
  end

  defp reject_positional!([]), do: :ok

  defp reject_positional!(positional) do
    Mix.raise(
      "mix capstone.gen.config takes no positional arguments, got: #{inspect(positional)}"
    )
  end
end
