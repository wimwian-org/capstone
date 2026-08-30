defmodule Mix.Tasks.Openbao.SetupTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Openbao.Setup

  setup do
    Application.put_env(:new_api_app, Setup, plug: {Req.Test, Setup})
    on_exit(fn -> Application.delete_env(:new_api_app, Setup) end)
  end

  test "enables approle, creates a role, and prints role_id/secret_id" do
    Req.Test.stub(Setup, fn conn ->
      case {conn.method, conn.request_path} do
        {"POST", "/v1/sys/auth/approle"} ->
          Plug.Conn.send_resp(conn, 204, "")

        {"PUT", "/v1/sys/policies/acl/new_api_app-read"} ->
          Plug.Conn.send_resp(conn, 204, "")

        {"POST", "/v1/auth/approle/role/new_api_app"} ->
          Plug.Conn.send_resp(conn, 204, "")

        {"GET", "/v1/auth/approle/role/new_api_app/role-id"} ->
          Req.Test.json(conn, %{"data" => %{"role_id" => "role-123"}})

        {"POST", "/v1/auth/approle/role/new_api_app/secret-id"} ->
          Req.Test.json(conn, %{"data" => %{"secret_id" => "secret-456"}})
      end
    end)

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Setup.run(["--base-url", "http://localhost:8200", "--root-token", "dev-root"])
      end)

    assert output =~ "role_id: role-123"
    assert output =~ "secret_id: secret-456"
  end

  test "raises without --base-url or --root-token" do
    assert_raise Mix.Error, ~r/requires --base-url and --root-token/, fn -> Setup.run([]) end
  end
end
