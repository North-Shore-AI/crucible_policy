defmodule CruciblePolicyTest do
  use ExUnit.Case
  doctest CruciblePolicy

  test "exposes package version" do
    assert CruciblePolicy.version() == "0.1.0"
  end
end
