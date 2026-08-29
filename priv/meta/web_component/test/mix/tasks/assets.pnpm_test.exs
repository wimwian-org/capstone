defmodule Mix.Tasks.Assets.PnpmTest do
  use ExUnit.Case, async: false

  @fake_pnpm_script """
  #!/bin/sh
  printf '%s\\n' "$@" > "$FAKE_PNPM_LOG"
  exit "${FAKE_PNPM_EXIT_CODE:-0}"
  """

  setup do
    original_path = System.get_env("PATH") || ""

    tmp_dir =
      Path.join(System.tmp_dir!(), "assets_pnpm_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      System.put_env("PATH", original_path)
      System.delete_env("FAKE_PNPM_LOG")
      System.delete_env("FAKE_PNPM_EXIT_CODE")
      File.rm_rf!(tmp_dir)
    end)

    %{tmp_dir: tmp_dir}
  end

  defp install_fake_pnpm!(tmp_dir) do
    bin_dir = Path.join(tmp_dir, "bin")
    File.mkdir_p!(bin_dir)
    pnpm_path = Path.join(bin_dir, "pnpm")
    File.write!(pnpm_path, @fake_pnpm_script)
    File.chmod!(pnpm_path, 0o755)
    System.put_env("PATH", bin_dir <> ":" <> (System.get_env("PATH") || ""))

    log_path = Path.join(tmp_dir, "pnpm_invocation.log")
    System.put_env("FAKE_PNPM_LOG", log_path)
    log_path
  end

  test "raises a usage error when no script is given" do
    assert_raise Mix.Error, "Usage: mix assets.pnpm <script> [-- extra args]", fn ->
      Mix.Tasks.Assets.Pnpm.run([])
    end
  end

  test "raises when assets/ is missing", %{tmp_dir: tmp_dir} do
    assert_raise Mix.Error,
                 "assets/ not found — this project has no live_svelte asset pipeline (07-assets.md)",
                 fn ->
                   File.cd!(tmp_dir, fn ->
                     Mix.Tasks.Assets.Pnpm.run(["build"])
                   end)
                 end
  end

  test "runs the pnpm script with extra args from assets/", %{tmp_dir: tmp_dir} do
    File.mkdir_p!(Path.join(tmp_dir, "assets"))
    log_path = install_fake_pnpm!(tmp_dir)

    File.cd!(tmp_dir, fn ->
      Mix.Tasks.Assets.Pnpm.run(["build", "--", "--watch"])
    end)

    assert File.read!(log_path) == "run\nbuild\n--\n--watch\n"
  end

  test "raises when the pnpm script exits with a non-zero code", %{tmp_dir: tmp_dir} do
    File.mkdir_p!(Path.join(tmp_dir, "assets"))
    install_fake_pnpm!(tmp_dir)
    System.put_env("FAKE_PNPM_EXIT_CODE", "7")

    assert_raise Mix.Error, "pnpm run build (in assets/) failed with exit code 7", fn ->
      File.cd!(tmp_dir, fn ->
        Mix.Tasks.Assets.Pnpm.run(["build"])
      end)
    end
  end
end
