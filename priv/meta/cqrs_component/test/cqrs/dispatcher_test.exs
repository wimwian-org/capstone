defmodule NewApiApp.CQRS.DispatcherTest do
  use ExUnit.Case, async: false

  alias Commanded.EventStore.Adapters.InMemory
  alias NewApiApp.CQRS.App
  alias NewApiApp.CQRS.Cache
  alias NewApiApp.CQRS.Dispatcher
  alias NewApiApp.CQRS.UniqueCheck

  defmodule CreateFixture do
    @behaviour NewApiApp.CQRS.Command

    defstruct [:email]

    @impl true
    def build(params), do: %__MODULE__{email: params.email}

    @impl true
    def schema_tag, do: :fixture

    @impl true
    def unique_fields, do: [[:email]]
  end

  setup do
    InMemory.reset!(App)
    :ok
  end

  test "a command whose unique field is already reserved is fast-rejected" do
    email = "taken-#{System.unique_integer([:positive])}@example.com"
    assert {:ok, _reserved} = UniqueCheck.reserve(:fixture, [[:email]], %{email: email})

    assert {:error, {:already_taken, [:email]}} =
             Dispatcher.dispatch(CreateFixture, %{email: email})
  end
end
