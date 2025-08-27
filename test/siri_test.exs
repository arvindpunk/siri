defmodule SiriTest do
  use ExUnit.Case
  doctest Siri

  test "greets the world" do
    assert Siri.hello() == :world
  end
end
