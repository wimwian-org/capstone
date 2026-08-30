defmodule NewApiApp.VaultTest do
  use ExUnit.Case, async: false

  @plug_opts [plug: {Req.Test, NewApiApp.Vault}]

  setup do
    # The application supervisor already runs a permanently-registered
    # `NewApiApp.Vault.Auth` — a test-scoped instance under the same name
    # would collide with it, so this one registers under a distinct name.
    # `Auth.current_token/0` reads a module-keyed `:persistent_term`, not
    # this name, so `read_secret/2`'s token lookup is unaffected.
    start_supervised!({NewApiApp.Vault.Auth, name: :vault_test_auth})
    :ok
  end

  test "returns the decoded KV v2 secret data on a 200" do
    Req.Test.stub(NewApiApp.Vault, fn conn ->
      assert conn.request_path == "/v1/secret/data/new_api_app/db"
      assert Plug.Conn.get_req_header(conn, "x-vault-token") == ["new_api_app-dev-root-token"]

      Req.Test.json(conn, %{"data" => %{"data" => %{"username" => "new_api_app"}}})
    end)

    assert NewApiApp.Vault.read_secret("new_api_app/db", @plug_opts) ==
             {:ok, %{"username" => "new_api_app"}}
  end

  test "returns :not_found on a 404" do
    Req.Test.stub(NewApiApp.Vault, fn conn -> Plug.Conn.send_resp(conn, 404, "") end)

    assert NewApiApp.Vault.read_secret("new_api_app/missing", @plug_opts) == {:error, :not_found}
  end

  test "returns the status for any other response" do
    Req.Test.stub(NewApiApp.Vault, fn conn -> Plug.Conn.send_resp(conn, 500, "") end)

    # retry: false — a raw 500 would otherwise trigger Req's built-in
    # retry-with-backoff, which sleeps for real between attempts.
    assert NewApiApp.Vault.read_secret("new_api_app/db", [retry: false] ++ @plug_opts) ==
             {:error, {:unexpected_status, 500}}
  end

  test "health/0 returns :ok on a 200 with no auth header required" do
    Req.Test.stub(NewApiApp.Vault, fn conn ->
      refute Plug.Conn.get_req_header(conn, "x-vault-token") != []
      Plug.Conn.send_resp(conn, 200, "")
    end)

    assert NewApiApp.Vault.health(@plug_opts) == :ok
  end
end

defmodule NewApiApp.Vault.LiveApproleTest do
  use ExUnit.Case, async: false

  # Exercises the real OpenBao sidecar's AppRole login — excluded by
  # default (see test/test_helper.exs), opt in with `mix test --include
  # openbao`. Prerequisite: `mix openbao.setup --base-url
  # http://localhost:8200 --root-token new_api_app-dev-root-token` has
  # already been run against the running dev-mode sidecar, and ROLE_ID/
  # SECRET_ID are exported from its output — same prerequisite pattern the
  # toolchain tests already document for pnpm/phx_new.
  @moduletag :openbao

  # The application supervisor already runs a permanently-registered
  # `NewApiApp.Vault.Auth` (booted from config/test.exs's static token) — a
  # test-scoped instance under the same name would collide with it, so this
  # one registers under this distinct name instead. `Auth.current_token/0`
  # reads a module-keyed `:persistent_term`, not this name, so this test's
  # own successful login — the last write to that key immediately before the
  # assertion — is unaffected by which name the process registers under.
  @name :live_approle_test_auth

  test "an approle-configured Auth authenticates against the real sidecar" do
    role_id = System.fetch_env!("OPENBAO_TEST_ROLE_ID")
    secret_id = System.fetch_env!("OPENBAO_TEST_SECRET_ID")

    # Snapshot the actual configured value and restore that exact snapshot,
    # rather than hand-writing a restoration literal that can silently drift
    # from what config/test.exs actually specifies (see Task 10's review).
    original = Application.get_env(:new_api_app, NewApiApp.Vault)

    Application.put_env(:new_api_app, NewApiApp.Vault,
      base_url: "http://localhost:8200",
      method: :approle,
      role_id: role_id,
      secret_id: secret_id,
      mount: "approle",
      timeout_ms: 5_000
    )

    on_exit(fn ->
      Application.put_env(:new_api_app, NewApiApp.Vault, original)
    end)

    {:ok, pid} = NewApiApp.Vault.Auth.start_link(name: @name)
    assert is_binary(NewApiApp.Vault.Auth.current_token())
    GenServer.stop(pid)
  end

  test "health/0 succeeds against the real sidecar with no token configured" do
    assert NewApiApp.Vault.health() == :ok
  end
end
