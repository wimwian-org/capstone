defmodule NewApiApp.GRPC.Credentials do
  @moduledoc """
  Builds the GRPC.Credential shared by the server's supervision child and
  NewApiApp.GRPC.Client — both sides of this plugin's gRPC infrastructure
  are TLS-required, no plaintext fallback.
  """

  @doc "Server-side credential: presents this app's own certificate."
  @spec server_credential() :: GRPC.Credential.t()
  def server_credential do
    config = Application.fetch_env!(:new_api_app, __MODULE__)

    GRPC.Credential.new(
      ssl: [
        certfile: Keyword.fetch!(config, :certfile),
        keyfile: Keyword.fetch!(config, :keyfile)
      ]
    )
  end

  @doc "Client-side credential: trusts the given CA when calling another service."
  @spec client_credential() :: GRPC.Credential.t()
  def client_credential do
    config = Application.fetch_env!(:new_api_app, __MODULE__)

    GRPC.Credential.new(ssl: [cacertfile: Keyword.fetch!(config, :cacertfile)])
  end
end
