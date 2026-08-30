defmodule NewApiApp.Vault.AuthTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias NewApiApp.Vault.Auth

  # The application supervisor already runs a permanently-registered
  # `NewApiApp.Vault.Auth` (booted from config/test.exs's static token) — a
  # test-scoped instance under the same name would collide with it, so every
  # `start_supervised!` below registers under this distinct name instead.
  # `Auth.current_token/0` reads a module-keyed `:persistent_term`, not this
  # name, so it is unaffected by the rename.
  @name :auth_test_process

  setup do
    original = Application.get_env(:new_api_app, NewApiApp.Vault)

    Application.put_env(:new_api_app, NewApiApp.Vault,
      base_url: "http://localhost:8200",
      method: :token,
      token: "static-token",
      role_id: nil,
      secret_id: nil,
      mount: "approle",
      timeout_ms: 1_000
    )

    # Restore the exact snapshot taken above, not a hand-written partial
    # subset — a partial restore would leave later tests (e.g. VaultTest's
    # own `start_supervised!` with no override) depending on whatever the
    # last-run AuthTest test happened to `put_env`, since cross-module test
    # order isn't guaranteed.
    on_exit(fn ->
      Application.put_env(:new_api_app, NewApiApp.Vault, original)
    end)

    :ok
  end

  test ":token method publishes the configured static token and never calls out" do
    start_supervised!({Auth, name: @name})
    assert Auth.current_token() == "static-token"
  end

  test ":approle method: a successful login publishes current_token/0 and schedules renewal" do
    Application.put_env(:new_api_app, NewApiApp.Vault,
      base_url: "http://localhost:8200",
      method: :approle,
      role_id: "role-1",
      secret_id: "secret-1",
      mount: "approle",
      timeout_ms: 1_000,
      plug: {Req.Test, NewApiApp.Vault.Auth}
    )

    Req.Test.stub(NewApiApp.Vault.Auth, fn conn ->
      assert conn.request_path == "/v1/auth/approle/login"

      Req.Test.json(conn, %{
        "auth" => %{"client_token" => "approle-token", "lease_duration" => 3_600}
      })
    end)

    start_supervised!({Auth, name: @name})
    assert Auth.current_token() == "approle-token"
  end

  test ":approle method: a failing initial login stops the GenServer (fail-closed boot gate)" do
    Application.put_env(:new_api_app, NewApiApp.Vault,
      base_url: "http://localhost:8200",
      method: :approle,
      role_id: "wrong",
      secret_id: "wrong",
      mount: "approle",
      timeout_ms: 1_000,
      plug: {Req.Test, NewApiApp.Vault.Auth}
    )

    Req.Test.stub(NewApiApp.Vault.Auth, fn conn ->
      Plug.Conn.send_resp(conn, 400, Jason.encode!(%{"errors" => ["invalid role or secret ID"]}))
    end)

    Process.flag(:trap_exit, true)

    # Asserting the specific {:unexpected_status, 400} reason (not a bare
    # {:error, _reason} wildcard) matters here: a wildcard can't distinguish
    # the fail-closed gate genuinely refusing to boot from any other startup
    # failure, including a name collision with an already-running Auth
    # (start_supervised also returns {:error, {:already_started, pid}} in
    # that case) — exactly the failure mode this test is meant to catch.
    assert {:error, {{:unexpected_status, 400}, _child}} =
             start_supervised({Auth, name: @name})
  end

  test ":approle method: a renewal failure re-triggers a full login rather than crashing" do
    Application.put_env(:new_api_app, NewApiApp.Vault,
      base_url: "http://localhost:8200",
      method: :approle,
      role_id: "role-1",
      secret_id: "secret-1",
      mount: "approle",
      timeout_ms: 1_000,
      plug: {Req.Test, NewApiApp.Vault.Auth}
    )

    parent = self()

    Req.Test.stub(NewApiApp.Vault.Auth, fn conn ->
      case conn.request_path do
        "/v1/auth/approle/login" ->
          send(parent, :logged_in)
          Req.Test.json(conn, %{"auth" => %{"client_token" => "t1", "lease_duration" => 1}})

        "/v1/auth/token/renew-self" ->
          Plug.Conn.send_resp(conn, 500, "")
      end
    end)

    pid = start_supervised!({Auth, name: @name})
    assert_receive :logged_in, 1_000

    # lease_duration: 1s * 2/3 renew_fraction ~= 667ms, floored to
    # schedule_renew/1's 1_000ms minimum, until :renew fires and fails
    # (renew-self always 500s above), which must re-trigger a full login
    # rather than crashing the process.
    ref = Process.monitor(pid)
    refute_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_500
    assert Process.alive?(pid)
  end

  test ":approle method: a lease_duration of 0 does not schedule a renewal (no request flood)" do
    Application.put_env(:new_api_app, NewApiApp.Vault,
      base_url: "http://localhost:8200",
      method: :approle,
      role_id: "role-1",
      secret_id: "secret-1",
      mount: "approle",
      timeout_ms: 1_000,
      plug: {Req.Test, NewApiApp.Vault.Auth}
    )

    parent = self()

    Req.Test.stub(NewApiApp.Vault.Auth, fn conn ->
      send(parent, {:request, conn.request_path})
      Req.Test.json(conn, %{"auth" => %{"client_token" => "t0", "lease_duration" => 0}})
    end)

    start_supervised!({Auth, name: @name})
    assert_receive {:request, "/v1/auth/approle/login"}, 1_000
    assert Auth.current_token() == "t0"

    # Pre-fix, `schedule_renew(0)` called `Process.send_after(self(),
    # :renew, 0)`, and a renewal that keeps succeeding with ttl: 0 becomes a
    # tight infinite request loop — this would show up as more requests
    # arriving well within this window.
    refute_receive {:request, _path}, 300
  end

  test ":approle method: a missing lease_duration does not crash the process" do
    Application.put_env(:new_api_app, NewApiApp.Vault,
      base_url: "http://localhost:8200",
      method: :approle,
      role_id: "role-1",
      secret_id: "secret-1",
      mount: "approle",
      timeout_ms: 1_000,
      plug: {Req.Test, NewApiApp.Vault.Auth}
    )

    Req.Test.stub(NewApiApp.Vault.Auth, fn conn ->
      # No "lease_duration" key at all — auth["lease_duration"] resolves to
      # nil. Pre-fix, `schedule_renew(nil)` raised ArithmeticError out of
      # `round(nil * 1000 * ...)` inside the synchronous `init/1` login,
      # crashing the boot attempt outright instead of just failing it.
      Req.Test.json(conn, %{"auth" => %{"client_token" => "nil-ttl-token"}})
    end)

    pid = start_supervised!({Auth, name: @name})
    assert Auth.current_token() == "nil-ttl-token"
    assert Process.alive?(pid)
  end

  test ":approle method: a malformed 200 renewal response never logs the response body (no token leakage)" do
    Application.put_env(:new_api_app, NewApiApp.Vault,
      base_url: "http://localhost:8200",
      method: :approle,
      role_id: "role-1",
      secret_id: "secret-1",
      mount: "approle",
      timeout_ms: 1_000,
      plug: {Req.Test, NewApiApp.Vault.Auth}
    )

    Req.Test.stub(NewApiApp.Vault.Auth, fn conn ->
      case conn.request_path do
        "/v1/auth/approle/login" ->
          Req.Test.json(conn, %{"auth" => %{"client_token" => "t1", "lease_duration" => 3_600}})

        "/v1/auth/token/renew-self" ->
          # A 200 that doesn't match the expected `%{"auth" =>
          # %{"lease_duration" => ttl}}` shape — a real OpenBao renew-self
          # response legitimately carries `auth.client_token`, so this
          # simulates a live token landing in renew_result/1's fallback
          # clause.
          Req.Test.json(conn, %{"auth" => %{"client_token" => "should-never-be-logged"}})
      end
    end)

    pid = start_supervised!({Auth, name: @name})

    log =
      capture_log(fn ->
        send(pid, :renew)
        Process.sleep(50)
      end)

    refute log =~ "should-never-be-logged"
    assert log =~ "unexpected_status"
  end
end
