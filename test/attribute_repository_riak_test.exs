defmodule AttributeRepositoryRiakTest do
  use ExUnit.Case
  doctest AttributeRepositoryRiak

  test "greets the world" do
    assert AttributeRepositoryRiak.hello() == :world
  end
end
