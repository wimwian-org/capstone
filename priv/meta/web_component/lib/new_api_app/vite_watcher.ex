defmodule NewApiApp.ViteWatcher do
  @moduledoc """
  Runs `pnpm exec vite dev` from `assets/` as a Phoenix endpoint watcher (dev only).

  Configured via the `{module, function, args}` watcher form, whose return value Phoenix's watcher
  supervisor discards (only the `{cmd, args}` form gets exit-status checking) — so a failed command
  has to raise/exit loudly itself, or Vite dies silently while the dev server keeps running against
  a dead backend.
  """

  require Logger

  def run do
    case System.cmd("pnpm", ["exec", "vite", "dev"],
           cd: Path.join(File.cwd!(), "assets"),
           into: IO.stream(:stdio, :line),
           stderr_to_stdout: true
         ) do
      {_output, 0} = result ->
        result

      {_output, status} ->
        Logger.error(
          "NewApiApp.ViteWatcher: `pnpm exec vite dev` exited with status #{status} — Vite failed to " <>
            "start (a port 5173 conflict is a likely cause, since vite.config.mjs sets " <>
            "strictPort: true). The dev server is now running without a working Vite backend."
        )

        exit(:vite_watcher_command_error)
    end
  rescue
    e in ErlangError ->
      case e do
        %ErlangError{original: :enoent} ->
          Logger.error(
            "NewApiApp.ViteWatcher: pnpm not found on PATH — install pnpm to run the Vite dev watcher."
          )

          exit(:vite_watcher_pnpm_not_found)

        _other ->
          reraise e, __STACKTRACE__
      end
  end
end
