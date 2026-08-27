defmodule Capstone.Config.SecurityTest do
  use ExUnit.Case, async: true

  alias Capstone.Config.Security

  test "from_keyword/2 builds a struct with both fields given" do
    assert Security.from_keyword([envelope_encryption: true, cloak: true], [:security]) ==
             {:ok, %Security{envelope_encryption: true, cloak: true}}
  end

  test "from_keyword/2 defaults both fields to false when absent" do
    assert Security.from_keyword([], [:security]) ==
             {:ok, %Security{envelope_encryption: false, cloak: false}}
  end

  test "from_keyword/2 reports a non-boolean field" do
    assert {:error, [{:invalid_type, [:security, :cloak], _, "yes"}]} =
             Security.from_keyword([cloak: "yes"], [:security])
  end

  test "from_keyword/2 reports an unknown key" do
    assert {:error, [{:unknown_key, [:security], :typo}]} =
             Security.from_keyword([typo: true], [:security])
  end

  test "from_keyword/2 collects an unknown key and an invalid type together" do
    assert {:error, errors} =
             Security.from_keyword([cloak: "yes", typo: true], [:security])

    assert {:unknown_key, [:security], :typo} in errors
    assert Enum.any?(errors, &match?({:invalid_type, [:security, :cloak], _, "yes"}, &1))
    assert length(errors) == 2
  end
end
