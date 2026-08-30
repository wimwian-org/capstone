defmodule NewApiApp.Vault do
  @moduledoc "Reads secrets from the OpenBao (Vault-compatible) sidecar's KV v2 HTTP API."

  alias NewApiApp.Vault.Auth

  @doc """
  Reads the secret at `path` (e.g. `"new_api_app/db"`).

  `opts` are merged into the underlying `Req.new/1` call — tests use this to
  inject a `:plug` stub (see `Req.Test`) instead of hitting a real OpenBao
  instance.
  """
  def read_secret(path, opts \\ []) do
    config = Application.fetch_env!(:new_api_app, __MODULE__)
    base_url = Keyword.fetch!(config, :base_url)
    token = Auth.current_token()

    req_opts =
      Keyword.merge(
        [
          base_url: base_url,
          headers: [{"x-vault-token", token}],
          receive_timeout: config[:timeout_ms],
          retry: false
        ],
        opts
      )

    request = Req.new(req_opts)

    case Req.get(request, url: "/v1/secret/data/#{path}") do
      {:ok, %Req.Response{status: 200, body: %{"data" => %{"data" => data}}}} ->
        {:ok, data}

      {:ok, %Req.Response{status: 404}} ->
        {:error, :not_found}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Checks the OpenBao sidecar's own health endpoint — no auth header needed.

  `opts` are merged into the underlying `Req.new/1` call, same as
  `read_secret/2`.
  """
  def health(opts \\ []) do
    config = Application.fetch_env!(:new_api_app, __MODULE__)
    base_url = Keyword.fetch!(config, :base_url)

    req_opts =
      Keyword.merge(
        [base_url: base_url, retry: false, receive_timeout: config[:timeout_ms]],
        opts
      )

    case Req.get(Req.new(req_opts), url: "/v1/sys/health") do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      {:ok, %Req.Response{status: status}} -> {:error, {:unexpected_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
