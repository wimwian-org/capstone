defmodule Capstone.Config.FieldsTest do
  use ExUnit.Case, async: true

  alias Capstone.Config.Fields

  describe "unknown_key_errors/3" do
    test "flags every key not in the known set" do
      assert Fields.unknown_key_errors([a: 1, b: 2], [:a], [:section]) ==
               [{:unknown_key, [:section], :b}]
    end

    test "returns [] when every key is known" do
      assert Fields.unknown_key_errors([a: 1], [:a, :b], [:section]) == []
    end
  end

  describe "missing_key_errors/3" do
    test "flags every required key absent from fields" do
      assert Fields.missing_key_errors([a: 1], [:a, :b], [:section]) ==
               [{:missing_key, [:section, :b]}]
    end

    test "returns [] when every required key is present" do
      assert Fields.missing_key_errors([a: 1, b: 2], [:a, :b], [:section]) == []
    end
  end

  describe "typed_field_errors/5" do
    test "returns [] when the key is absent" do
      assert Fields.typed_field_errors([], :a, [:section], "boolean()", &is_boolean/1) == []
    end

    test "returns [] when the present value satisfies the predicate" do
      assert Fields.typed_field_errors([a: true], :a, [:section], "boolean()", &is_boolean/1) ==
               []
    end

    test "reports {:invalid_type, ...} when the present value fails the predicate" do
      assert Fields.typed_field_errors([a: "yes"], :a, [:section], "boolean()", &is_boolean/1) ==
               [{:invalid_type, [:section, :a], "boolean()", "yes"}]
    end
  end

  describe "boolean_field_errors/3" do
    test "returns [] when the key is absent" do
      assert Fields.boolean_field_errors([], :a, [:section]) == []
    end

    test "returns [] when the present value is a boolean" do
      assert Fields.boolean_field_errors([a: false], :a, [:section]) == []
    end

    test "reports {:invalid_type, ..., \"boolean()\", ...} for a non-boolean value" do
      assert Fields.boolean_field_errors([a: 1], :a, [:section]) ==
               [{:invalid_type, [:section, :a], "boolean()", 1}]
    end
  end
end
