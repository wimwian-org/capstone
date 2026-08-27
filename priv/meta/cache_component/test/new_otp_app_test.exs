defmodule NewOtpAppTest do
  use ExUnit.Case
  doctest NewOtpApp

  test "greets the world" do
    assert NewOtpApp.hello() == :world
  end
end
