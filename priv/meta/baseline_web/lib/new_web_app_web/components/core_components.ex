defmodule NewWebAppWeb.CoreComponents do
  @moduledoc """
  Holds the Svelte app-shell mount (`app_shell/1`).

  All HEEx UI rendering lives in Svelte components sourced from `sv5ui`, so
  this module carries the mount and nothing else. `phx.new` generates a library
  of HEEx atoms here for a full web project; this baseline is `--no-html`, so
  there were none to delete — the composition never creates them.
  """

  use Phoenix.Component

  # `LiveSvelte`, not `LiveSvelte.Components`: `<.svelte>` is defined on the
  # module itself, and importing the other yields `undefined function svelte/1`.
  import LiveSvelte

  @doc """
  Mounts the persistent Svelte `AppShell` beside the page's own content.

  `<.svelte>` mounts into its own hook-owned DOM subtree and does not accept
  server-rendered HEEx as reactive children, so the shell is an independent
  sibling of `<main>` rather than a wrapper around it. From here on this
  function owns the `<main>` wrapper; a layout must not add a second one.

  `socket` is `default: nil` rather than required because `app_shell/1` is
  reachable from dead renders too, where nil is exactly what `live_svelte`'s
  own attr defaults to. Passing a connected socket lets it skip an SSR
  round-trip and send prop diffs instead of full props.
  """
  attr :flash, :map, required: true
  attr :socket, :map, default: nil
  slot :inner_block, required: true

  def app_shell(assigns) do
    ~H"""
    <.svelte name="AppShell" props={%{flash: @flash}} socket={@socket} />
    <main>
      {render_slot(@inner_block)}
    </main>
    """
  end
end
