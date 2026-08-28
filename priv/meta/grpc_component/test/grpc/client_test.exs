defmodule NewApiApp.GRPC.ClientTest do
  use ExUnit.Case, async: true

  alias NewApiApp.GRPC.Client

  test "connects to the app's own already-running gRPC server over TLS" do
    port = Application.fetch_env!(:new_api_app, NewApiApp.GRPC.Endpoint)[:port]

    assert {:ok, channel} = Client.connect("localhost:#{port}")
    assert %GRPC.Channel{} = channel
  end
end
