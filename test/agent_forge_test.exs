defmodule AgentForgeTest do
  use ExUnit.Case
  doctest AgentForge

  alias AgentForge.{Signal, Store}

  # Each test gets a unique store to avoid conflicts
  setup do
    store_name = :"store_#{System.unique_integer()}"
    start_supervised!({Store, name: store_name})
    %{store: store_name}
  end

  describe "new_flow/2" do
    test "creates a usable flow" do
      handler = fn signal, state ->
        {Signal.emit(:echo, signal.data), state}
      end

      flow = AgentForge.new_flow([handler])
      signal = AgentForge.new_signal(:test, "hello")
      {:ok, result, _state} = flow.(signal)

      assert result.type == :echo
      assert result.data == "hello"
    end
  end

  describe "new_stateful_flow/2" do
    test "maintains state across calls", %{store: store} do
      counter = fn _signal, state ->
        count = Map.get(state, :count, 0) + 1
        {Signal.emit(:count, count), Map.put(state, :count, count)}
      end

      store_key = :test_counter
      flow = AgentForge.new_stateful_flow(
        [counter],
        store_name: store,
        store_key: store_key
      )

      signal = AgentForge.new_signal(:inc, nil)

      {:ok, result1, _} = flow.(signal)
      {:ok, result2, _} = flow.(signal)

      assert result1.data == 1
      assert result2.data == 2
    end
  end

  describe "delegated Signal functions" do
    test "new_signal/3 creates signals" do
      signal = AgentForge.new_signal(:test, "data")
      assert signal.type == :test
      assert signal.data == "data"
    end

    test "emit/3 creates emit results" do
      {:emit, signal} = AgentForge.emit(:test, "data")
      assert signal.type == :test
      assert signal.data == "data"
    end

    test "emit_many/1 creates multi-signal results" do
      {:emit_many, signals} = AgentForge.emit_many([
        {:test1, "data1"},
        {:test2, "data2"}
      ])
      assert length(signals) == 2
    end

    test "halt/1 creates halt results" do
      assert AgentForge.halt("done") == {:halt, "done"}
    end
  end
end
