# NewApiApp

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

## gRPC

This project has both a gRPC server (`NewApiApp.GRPC.Endpoint`) and a gRPC client
(`NewApiApp.GRPC.Client`), TLS-required on both sides — no plaintext fallback.

### Setup

A self-signed dev/test certificate is already generated and committed
(`priv/cert/grpc_selfsigned.pem`/`grpc_selfsigned_key.pem`) — for production, replace these paths
in `config/runtime.exs` with real certificate paths (env vars), the same way `NewApiApp.Repo`'s
production credentials are already handled there.

To regenerate the dev/test cert (e.g. to add more hostnames):

```bash
mix new_api_app.grpc.gen.cert my-service.localhost
```

To compile `.proto` files (requires `protoc` and `protoc-gen-elixir` installed — see
https://grpc.io/docs/protoc-installation/ and the `protobuf` Hex package's own install docs):

```bash
mix new_api_app.grpc.gen
```

This compiles every `.proto` file under `priv/protos/` into `lib/new_api_app/grpc/generated/`.

### Worked example

```elixir
# priv/protos/greeter.proto
syntax = "proto3";

package greeter;

service Greeter {
  rpc SayHello (HelloRequest) returns (HelloReply) {}
}

message HelloRequest {
  string name = 1;
}

message HelloReply {
  string message = 1;
}
```

```bash
mix new_api_app.grpc.gen
```

```elixir
# A developer's own service implementation — NOT shipped by this plugin.
defmodule NewApiApp.Greeter.Server do
  use GRPC.Server, service: Greeter.Greeter.Service

  @impl true
  def say_hello(request, _stream) do
    %Greeter.HelloReply{message: "Hello, #{request.name}!"}
  end
end
```

Add your service to `NewApiApp.GRPC.Endpoint`:

```elixir
defmodule NewApiApp.GRPC.Endpoint do
  use GRPC.Endpoint

  run [NewApiApp.Greeter.Server]
end
```

Call it from a client (this project's own, or a different one entirely):

```elixir
{:ok, channel} = NewApiApp.GRPC.Client.connect("localhost:50051")
{:ok, reply} = channel |> Greeter.Greeter.Stub.say_hello(%Greeter.HelloRequest{name: "World"})
```

**Limitations:** no connection pooling (`NewApiApp.GRPC.Client.connect/1` is a one-shot,
stateless helper — build a pooled/supervised channel manager yourself if needed); no gRPC
reflection or health-checking services; no streaming RPC example (this plugin's worked example
covers a basic unary call only — `grpc`/`protobuf` fully support streaming, just not demonstrated
here); no mutual TLS (the server doesn't verify a client certificate) — extend
`NewApiApp.GRPC.Credentials.server_credential/0` yourself if you need that.
