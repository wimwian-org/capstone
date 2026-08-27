defmodule Capstone.ComponentTest do
  use ExUnit.Case, async: true

  alias Capstone.Plugin

  @plugin %{
    name: :valkey,
    version: "1.3.0",
    files: [{"lib/APP/cache.ex", :sole_owner}],
    deps: [{:nebulex, "~> 2.6"}]
  }

  test "write! then read! round-trips a plugin" do
    path = Path.join(System.tmp_dir!(), "plugin-#{:erlang.unique_integer([:positive])}.exs")
    on_exit(fn -> File.rm(path) end)

    assert :ok = Plugin.write!(path, @plugin)
    assert Plugin.read!(path) == @plugin
  end

  test "write! emits deterministic bytes" do
    a = Path.join(System.tmp_dir!(), "plugin-a-#{:erlang.unique_integer([:positive])}.exs")
    b = Path.join(System.tmp_dir!(), "plugin-b-#{:erlang.unique_integer([:positive])}.exs")

    on_exit(fn ->
      File.rm(a)
      File.rm(b)
    end)

    Plugin.write!(a, @plugin)
    Plugin.write!(b, @plugin)

    # D8: derive must be byte-stable so CI can assert the checked-in plugin
    # is current. Capstone.Source.encode!/1 sorts map keys to guarantee this.
    assert File.read!(a) == File.read!(b)
  end
end
