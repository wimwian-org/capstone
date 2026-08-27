defmodule Capstone.New.Project do
  @moduledoc """
  Edits to the freshly generated project.

  `render_config/1` uses a hand-rolled heredoc rather than calling
  `Capstone.Config`'s own encoder-equivalent, even though that codec is
  compiled locally in this project (`lib/capstone/config.ex`) and is
  perfectly reachable from here. That's a deliberate choice, not a
  limitation: unifying the reader and the writer behind one encoder is
  explicit future work, not done here. This project's own
  `test/capstone/config_test.exs` and `test/integration/target_project_test.exs`
  assert the rendered file is readable by `Capstone.Config`, which is the
  guarantee that actually matters in the meantime.
  """

  alias Capstone.New.Options

  @anchor "defp deps do\n    [\n"

  @doc "Splices `dep_line` in as the first entry of the generated project's `deps/0`."
  @spec patch_mix_exs(binary(), binary()) ::
          {:ok, binary()} | {:error, :deps_not_found | :already_patched}
  def patch_mix_exs(source, dep_line) do
    cond do
      String.contains?(source, ":capstone") ->
        {:error, :already_patched}

      not String.contains?(source, @anchor) ->
        {:error, :deps_not_found}

      true ->
        {:ok, String.replace(source, @anchor, @anchor <> "      #{dep_line},\n", global: false)}
    end
  end

  @doc "Renders `target.exs` — the SDD 8.1 slim input shape."
  @spec render_config(Options.t()) :: binary()
  def render_config(%Options{} = opts) do
    """
    %{
      schema_version: 1,
      base: #{inspect(opts.base)},
      project: [
        name: "#{opts.name}",
        module: #{inspect(opts.module)},
        app: #{inspect(opts.app)},
        github_org: "#{opts.github_org}"
      ],
      plugins: #{inspect(opts.plugins)}
    }
    """
  end
end
