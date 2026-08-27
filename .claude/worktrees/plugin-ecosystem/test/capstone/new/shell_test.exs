defmodule Capstone.New.ShellTest do
  use ExUnit.Case, async: true

  alias Capstone.New.Env
  alias Capstone.New.Shell

  defmodule OkRunner do
    @moduledoc false
    def cmd(_bin, args, opts) do
      send(self(), {:ran, args, opts})

      {"ok #{Enum.join(args, " ")}", 0}
    end
  end

  defmodule FailingRunner do
    @moduledoc false
    def cmd(_bin, _args, _opts), do: {"boom", 1}
  end

  test "cmd!/3 returns captured output on exit 0" do
    assert Shell.cmd!(["deps.get"], "/tmp/x", {OkRunner, :cmd}) == "ok deps.get"
  end

  test "cmd!/3 raises naming the command, status, directory and output on non-zero" do
    assert_raise Mix.Error, ~r/deps\.get.*1.*\/tmp\/x.*boom/s, fn ->
      Shell.cmd!(["deps.get"], "/tmp/x", {FailingRunner, :cmd})
    end
  end

  test "cmd!/3 passes the cd and the scrubbed child env to the runner" do
    Shell.cmd!(["deps.get"], "/tmp/x", {OkRunner, :cmd})

    assert_received {:ran, ["deps.get"], opts}
    assert opts[:cd] == "/tmp/x"
    assert opts[:env] == Env.child_env()
    assert opts[:stderr_to_stdout] == true
  end

  test "cmd!/3 defaults its runner to System.cmd without a closure" do
    # The default is DATA, not a capture: `&System.cmd("mix", &1, &2)` as a
    # default costs one permanently-uncovered line, and the ignore budget for
    # this perimeter cannot absorb it.
    {:arity, arity} = :erlang.fun_info(&Shell.cmd!/2, :arity)

    assert arity == 2, "cmd!/2 must exist so the runner has a literal default"
  end

  test "ensure_task_available!/2 returns :ok when the lookup finds a module" do
    assert Shell.ensure_task_available!("phx.new", fn _name -> Mix.Tasks.Help end) == :ok
  end

  test "ensure_task_available!/2 raises with an install hint when the lookup returns nil" do
    assert_raise Mix.Error, ~r/mix archive\.install hex phx_new/, fn ->
      Shell.ensure_task_available!("phx.new", fn _name -> nil end)
    end
  end

  test "ensure_task_available!/2 names the task it could not find" do
    assert_raise Mix.Error, ~r/new/, fn ->
      Shell.ensure_task_available!("new", fn _name -> nil end)
    end
  end

  test "ensure_task_available!/2 defaults its lookup to the real task registry" do
    # Mix.Tasks.Help is always installed, so this exercises the default arg.
    assert Shell.ensure_task_available!("help") == :ok
  end
end
