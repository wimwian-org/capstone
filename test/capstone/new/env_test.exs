defmodule Capstone.New.EnvTest do
  use ExUnit.Case, async: true

  alias Capstone.New.Env
  alias Capstone.New.Factory

  test "refuse_poisoned!/1 raises naming every set variable" do
    # Takes the env map as an argument, so no test mutates the real environment.
    # Scrubbing only the CHILD is insufficient: these corrupt the parent's own
    # project resolution. Measured — with MIX_BUILD_PATH set on the parent, both
    # System.cmd calls returned 0 yet the in-process re-point produced a
    # compile_path under the leaked directory.
    %{env: env} = Factory.build(:env_map, poisoned: ~w(MIX_EXS MIX_BUILD_PATH))

    assert_raise Mix.Error, ~r/MIX_EXS.*MIX_BUILD_PATH|MIX_BUILD_PATH.*MIX_EXS/s, fn ->
      Env.refuse_poisoned!(env)
    end
  end

  test "refuse_poisoned!/1 raises for each poisoning variable on its own" do
    for name <- ~w(MIX_EXS MIX_BUILD_PATH MIX_DEPS_PATH) do
      %{env: env} = Factory.build(:env_map, poisoned: [name])

      assert_raise Mix.Error, ~r/#{name}/, fn -> Env.refuse_poisoned!(env) end
    end
  end

  test "refuse_poisoned!/1 returns :ok for a clean env" do
    %{env: env} = Factory.build(:env_map)

    assert Env.refuse_poisoned!(env) == :ok
  end

  test "refuse_poisoned!/1 ignores variables that only affect the child" do
    # MIX_ENV is scrubbed from the child but does NOT corrupt the parent, so it
    # must not be a refusal. Conflating the two lists would make the archive
    # unusable inside any `MIX_ENV=test mix ...` invocation.
    %{env: env} = Factory.build(:env_map, set: %{"MIX_ENV" => "test"})

    assert Env.refuse_poisoned!(env) == :ok
  end

  test "child_env/0 nils the redirecting variables but keeps MIX_HOME and MIX_ARCHIVES" do
    child = Env.child_env()
    names = Enum.map(child, &elem(&1, 0))

    for name <- ~w(MIX_ENV MIX_EXS MIX_BUILD_PATH MIX_DEPS_PATH MIX_TARGET MIX_BUILD_ROOT) do
      assert {name, nil} in child
    end

    # The child needs both to find hex. MIX_ARCHIVES WINS over MIX_HOME under mise.
    refute "MIX_HOME" in names
    refute "MIX_ARCHIVES" in names
  end

  test "child_env/0 nils every variable it lists, and lists each once" do
    names = Enum.map(Env.child_env(), &elem(&1, 0))

    assert Enum.all?(Env.child_env(), &match?({_name, nil}, &1))
    assert names == Enum.uniq(names)
  end

  test "every variable that poisons the parent is also scrubbed from the child" do
    # A variable dangerous enough to refuse must not be handed to a subprocess.
    child_names = Enum.map(Env.child_env(), &elem(&1, 0))

    for name <- ~w(MIX_EXS MIX_BUILD_PATH MIX_DEPS_PATH) do
      assert name in child_names
    end
  end
end
