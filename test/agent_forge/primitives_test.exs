defmodule AgentForge.PrimitivesTest do
  use ExUnit.Case
  doctest AgentForge.Primitives

  alias AgentForge.{Primitives, Signal}

  describe "branch/3" do
    test "executes then_flow when condition is true" do
      branch = Primitives.branch(
        fn signal, _ -> signal.data > 10 end,
        [fn signal, state -> {Signal.emit(:high, signal.data), state} end],
        [fn signal, state -> {Signal.emit(:low, signal.data), state} end]
      )

      signal = Signal.new(:value, 15)
      {{:emit, result}, _state} = branch.(signal, %{})

      assert result.type == :high
      assert result.data == 15
    end

    test "executes else_flow when condition is false" do
      branch = Primitives.branch(
        fn signal, _ -> signal.data > 10 end,
        [fn signal, state -> {Signal.emit(:high, signal.data), state} end],
        [fn signal, state -> {Signal.emit(:low, signal.data), state} end]
      )

      signal = Signal.new(:value, 5)
      {{:emit, result}, _state} = branch.(signal, %{})

      assert result.type == :low
      assert result.data == 5
    end

    test "handles errors in flows" do
      branch = Primitives.branch(
        fn _, _ -> true end,
        [fn _, _ -> raise "Error in then flow" end],
        [fn signal, state -> {Signal.emit(:low, signal.data), state} end]
      )

      signal = Signal.new(:value, 15)
      {{:emit, result}, _state} = branch.(signal, %{})

      assert result.type == :error
      assert is_binary(result.data)
    end
  end

  describe "transform/1" do
    test "transforms signal data" do
      transform = Primitives.transform(&String.upcase/1)
      signal = Signal.new(:text, "hello")
      {{:emit, result}, _state} = transform.(signal, %{})

      assert result.type == :text
      assert result.data == "HELLO"
    end

    test "handles transform errors" do
      transform = Primitives.transform(fn _ -> raise "Transform error" end)
      signal = Signal.new(:text, "hello")
      {{:emit, result}, _state} = transform.(signal, %{})

      assert result.type == :error
      assert result.data =~ "Transform error"
    end
  end

  describe "loop/1" do
    test "processes each item and accumulates state" do
      handler = fn item, state ->
        {Signal.emit(:item, item), Map.update(state, :sum, item, &(&1 + item))}
      end

      loop = Primitives.loop(handler)
      signal = Signal.new(:list, [1, 2, 3])
      {{:emit_many, results}, state} = loop.(signal, %{})

      assert length(results) == 3
      assert state.sum == 6
      assert Enum.map(results, & &1.data) == [1, 2, 3]
    end

    test "handles non-list data" do
      handler = fn item, state -> {Signal.emit(:item, item), state} end
      loop = Primitives.loop(handler)
      signal = Signal.new(:value, "not a list")
      {{:emit, result}, _state} = loop.(signal, %{})

      assert result.type == :error
      assert result.data =~ "must be a list"
    end

    test "supports early termination with halt" do
      handler = fn item, state ->
        if item > 2 do
          {{:halt, "stopped at #{item}"}, state}
        else
          {Signal.emit(:item, item), state}
        end
      end

      loop = Primitives.loop(handler)
      signal = Signal.new(:list, [1, 2, 3, 4])
      {{:halt, result}, _state} = loop.(signal, %{})

      assert result == "stopped at 3"
    end
  end

  describe "sequence/1" do
    test "executes handlers in sequence" do
      handlers = [
        fn signal, state -> {Signal.emit(:step1, signal.data <> "_1"), state} end,
        fn signal, state -> {Signal.emit(:step2, signal.data <> "_2"), state} end
      ]

      sequence = Primitives.sequence(handlers)
      signal = Signal.new(:start, "data")
      {{:emit, result}, _state} = sequence.(signal, %{})

      assert result.type == :step2
      assert result.data == "data_1_2"
    end

    test "handles errors in sequence" do
      handlers = [
        fn signal, state -> {Signal.emit(:step1, signal.data), state} end,
        fn _, _ -> raise "Error in sequence" end
      ]

      sequence = Primitives.sequence(handlers)
      signal = Signal.new(:start, "data")
      {{:emit, result}, _state} = sequence.(signal, %{})

      assert result.type == :error
      assert is_binary(result.data)
    end
  end
end
