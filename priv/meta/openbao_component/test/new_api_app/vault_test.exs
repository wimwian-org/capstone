defmodule NewApiApp.VaultTest do
  use ExUnit.Case, async: true

  @plug_opts [plug: {Req.Test, NewApiApp.Vault}]

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
end
