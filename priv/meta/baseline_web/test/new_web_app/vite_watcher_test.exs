defmodule NewWebApp.ViteWatcherTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  test "shells out to pnpm exec vite dev from assets/, not npm" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "vite_watcher_test_#{System.unique_integer([:positive])}")

    bin_dir = Path.join(tmp_dir, "bin")
    File.mkdir_p!(bin_dir)

    log_path = Path.join(tmp_dir, "invocation.log")

    pnpm_path = Path.join(bin_dir, "pnpm")
    File.write!(pnpm_path, """
    #!/bin/sh
    printf '%s\\n' "$@" > "#{log_path}"
    exit 0
    """)
    File.chmod!(pnpm_path, 0o755)

    original_path = System.get_env("PATH") || ""
    System.put_env("PATH", bin_dir <> ":" <> original_path)

    on_exit(fn ->
      System.put_env("PATH", original_path)
      File.rm_rf!(tmp_dir)
    end)

    assert {_output, 0} = NewWebApp.ViteWatcher.run()
    assert File.read!(log_path) == "exec\nvite\ndev\n"
  end

  test "exits loudly (instead of returning) when pnpm exec vite dev exits non-zero" do
    put_fake_pnpm_on_path!("""
    #!/bin/sh
    exit 1
    """)

    log =
      capture_log(fn ->
        {pid, ref} = spawn_monitor(fn -> NewWebApp.ViteWatcher.run() end)
        assert_receive {:DOWN, ^ref, :process, ^pid, :vite_watcher_command_error}, 5_000
      end)

    assert log =~ "pnpm exec vite dev"
    assert log =~ "exited with status 1"
  end

  test "exits loudly with a clear message when pnpm isn't on PATH" do
    original_path = System.get_env("PATH") || ""
    System.put_env("PATH", "")

    on_exit(fn -> System.put_env("PATH", original_path) end)

    log =
      capture_log(fn ->
        {pid, ref} = spawn_monitor(fn -> NewWebApp.ViteWatcher.run() end)
        assert_receive {:DOWN, ^ref, :process, ^pid, :vite_watcher_pnpm_not_found}, 5_000
      end)

    assert log =~ "pnpm not found on PATH"
  end

  defp put_fake_pnpm_on_path!(script) do
    tmp_dir =
      Path.join(System.tmp_dir!(), "vite_watcher_test_#{System.unique_integer([:positive])}")

    bin_dir = Path.join(tmp_dir, "bin")
    File.mkdir_p!(bin_dir)

    pnpm_path = Path.join(bin_dir, "pnpm")
    File.write!(pnpm_path, script)
    File.chmod!(pnpm_path, 0o755)

    original_path = System.get_env("PATH") || ""
    System.put_env("PATH", bin_dir <> ":" <> original_path)

    on_exit(fn ->
      System.put_env("PATH", original_path)
      File.rm_rf!(tmp_dir)
    end)

    :ok
  end
end
