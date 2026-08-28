%{
  deps: [
    "{:grpc, \"~> 1.0\"}",
    "{:grpc_server, \"~> 1.0\"}",
    "{:protobuf, \"~> 0.13\"}",
    "{:mint, \"~> 1.9\"}"
  ],
  files: [
    {"lib/mix/tasks/APP.grpc.gen.cert.ex", :sole_owner},
    {"lib/mix/tasks/APP.grpc.gen.ex", :sole_owner},
    {"lib/APP/grpc/client.ex", :sole_owner},
    {"lib/APP/grpc/credentials.ex", :sole_owner},
    {"lib/APP/grpc/endpoint.ex", :sole_owner},
    {"priv/cert/grpc_selfsigned.pem", :sole_owner},
    {"priv/cert/grpc_selfsigned_key.pem", :sole_owner},
    {"test/grpc/client_test.exs", :sole_owner},
    {"README.md", :contributes, [key: :grpc_readme]},
    {"config/config.exs", :contributes, [key: :grpc_config, at: :before_import]},
    {"lib/APP/application.ex", :contributes,
     [
       key: :grpc_application,
       child:
         "{GRPC.Server.Supervisor,\n endpoint: <%= @module %>.GRPC.Endpoint,\n port: Application.fetch_env!(:<%= @app %>, <%= @module %>.GRPC.Endpoint)[:port],\n start_server: true,\n adapter_opts: [cred: <%= @module %>.GRPC.Credentials.server_credential()]}"
     ]}
  ],
  name: :grpc,
  version: "0.1.0"
}
