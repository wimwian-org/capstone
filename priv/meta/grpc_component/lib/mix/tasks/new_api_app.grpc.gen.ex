defmodule Mix.Tasks.NewApiApp.Grpc.Gen do
  @shortdoc "Compiles .proto files into Elixir gRPC service/message code"

  @moduledoc """
  Compiles every .proto file under priv/protos/ into
  lib/new_api_app/grpc/generated/.

  Requires `protoc` and `protoc-gen-elixir` installed on PATH — this task
  wraps the invocation, it does not install the compiler toolchain itself.
  """
  use Mix.Task

  @proto_dir "priv/protos"
  @out_dir "lib/new_api_app/grpc/generated"

  @impl Mix.Task
  def run(_args) do
    File.mkdir_p!(@out_dir)

    protos = Path.wildcard(Path.join(@proto_dir, "*.proto"))

    if protos == [] do
      Mix.shell().info("No .proto files found under #{@proto_dir}/ — nothing to generate.")
    else
      args = ["--elixir_out=plugins=grpc:#{@out_dir}", "--proto_path=#{@proto_dir}"] ++ protos

      case System.cmd("protoc", args, stderr_to_stdout: true) do
        {output, 0} -> Mix.shell().info(output)
        {output, code} -> Mix.raise("protoc exited with status #{code}:\n#{output}")
      end
    end
  end
end
