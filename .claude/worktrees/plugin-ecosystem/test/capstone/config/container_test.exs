defmodule Capstone.Config.ContainerTest do
  use ExUnit.Case, async: true

  alias Capstone.Config.Container
  alias Capstone.Config.Container.Sidecars

  describe "Sidecars.from_keyword/2" do
    test "builds a struct with all three sidecars given" do
      fields = [valkey: true, openbao: true, nginx: true]

      assert Sidecars.from_keyword(fields, [:container, :sidecars]) ==
               {:ok, %Sidecars{valkey: true, openbao: true, nginx: true}}
    end

    test "defaults every sidecar to false when absent" do
      assert Sidecars.from_keyword([], [:container, :sidecars]) == {:ok, %Sidecars{}}
    end

    test "reports a non-boolean sidecar value" do
      assert {:error, [{:invalid_type, [:container, :sidecars, :valkey], _, 1}]} =
               Sidecars.from_keyword([valkey: 1], [:container, :sidecars])
    end

    test "reports an unknown sidecar key" do
      assert {:error, [{:unknown_key, [:container, :sidecars], :redis}]} =
               Sidecars.from_keyword([redis: true], [:container, :sidecars])
    end
  end

  describe "Container.from_keyword/2" do
    test "builds a struct with local_ci and nested sidecars given" do
      fields = [local_ci: false, sidecars: [valkey: true]]

      assert Container.from_keyword(fields, [:container]) ==
               {:ok,
                %Container{
                  local_ci: false,
                  sidecars: %Sidecars{valkey: true, openbao: false, nginx: false}
                }}
    end

    test "defaults local_ci to true and sidecars to all-false when absent" do
      assert Container.from_keyword([], [:container]) ==
               {:ok, %Container{local_ci: true, sidecars: %Sidecars{}}}
    end

    test "reports a non-boolean local_ci" do
      assert {:error, [{:invalid_type, [:container, :local_ci], _, "yes"}]} =
               Container.from_keyword([local_ci: "yes"], [:container])
    end

    test "reports a non-list sidecars value" do
      assert {:error, [{:invalid_type, [:container, :sidecars], _, :not_a_list}]} =
               Container.from_keyword([sidecars: :not_a_list], [:container])
    end

    test "propagates a nested sidecars error with the full path" do
      assert {:error, [{:unknown_key, [:container, :sidecars], :redis}]} =
               Container.from_keyword([sidecars: [redis: true]], [:container])
    end

    test "reports an unknown top-level container key" do
      assert {:error, [{:unknown_key, [:container], :typo}]} =
               Container.from_keyword([typo: 1], [:container])
    end
  end
end
