defmodule Capstone.Check.TagXXX do
  @moduledoc """
  Blocks the build on an `XXX` comment tag.

  Credo ships built-in checks for `TODO` and `FIXME` but not for `XXX`, so this
  mirrors `Credo.Check.Design.TagTODO` with the tag name swapped. See
  `.claude/10-comment-tags.md`: `TODO`, `FIXME`, `BUG` and `XXX` block; the
  advisory six are deliberately unchecked.

  This module lives outside `lib/` on purpose — it is loaded by Credo through
  `requires:` in `.credo.exs`, never compiled into the application.
  """

  use Credo.Check,
    category: :design,
    exit_status: 2,
    param_defaults: [include_doc: true],
    explanations: [
      check: """
      XXX marks code the author already believes is wrong.

      Example:

          # XXX: this recomputes the whole index on every keystroke
          defp search(term) do
            # ...
          end

      An author flagging their own code as wrong is the cheapest bug report
      there is, so this blocks the build rather than reporting advice.
      """,
      params: [
        include_doc: "Set to `true` to also include tags from @doc attributes."
      ]
    ]

  alias Credo.Check.Design.TagHelper

  @tag_name "XXX"

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)

    source_file
    |> TagHelper.tags(@tag_name, ctx.params.include_doc)
    |> Enum.map(&issue_for(ctx, &1))
  end

  defp issue_for(ctx, {line_no, _line, trigger}) do
    format_issue(
      ctx,
      message: "Found a #{@tag_name} tag in a comment: #{trigger}",
      trigger: trigger,
      line_no: line_no
    )
  end
end
