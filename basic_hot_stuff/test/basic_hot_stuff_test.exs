defmodule BasicHotStuffTest do
  use ExUnit.Case
  doctest BasicHotStuff

  test "greets the world" do
    assert BasicHotStuff.hello() == :world
  end
end
