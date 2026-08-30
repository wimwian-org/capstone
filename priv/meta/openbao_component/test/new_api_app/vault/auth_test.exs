defmodule NewApiApp.Vault.AuthTest do
  use ExUnit.Case, async: false

  alias NewApiApp.Vault.Auth

  setup do
    Application.put_env(:new_api_app, NewApiApp.Vault,
      base_url: "http://localhost:8200",
      method: :token,
      token: "static-token",
      role_id: nil,
      secret_id: nil,
      mount: "approle",
      timeout_ms: 1_000
    )

    on_exit(fn ->
      Application.put_env(:new_api_app, NewApiApp.Vault,
        base_url: "http://localhost:8200",
        token: "new_api_app-dev-root-token"
      )
    end)

    :ok
  end

  test ":token method publishes the configured static token and never calls out" do
    start_supervised!(Auth)
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

    start_supervised!(Auth)
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
    assert {:error, _reason} = start_supervised(Auth)
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

    pid = start_supervised!(Auth)
    assert_receive :logged_in, 1_000

    # lease_duration: 1s * 2/3 renew_fraction ~= 667ms until :renew fires and
    # fails (renew-self always 500s above), which must re-trigger a full
    # login rather than crashing the process.
    ref = Process.monitor(pid)
    refute_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_500
    assert Process.alive?(pid)
  end
end
