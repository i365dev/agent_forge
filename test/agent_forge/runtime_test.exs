defmodule AgentForge.RuntimeTest do
  use ExUnit.Case
  doctest AgentForge.Runtime

  alias AgentForge.{Runtime, Signal, Store}

  # Each test gets a unique store to avoid conflicts
  setup do
    store_name = :"store_#{System.unique_integer()}"
    start_supervised!({Store, name: store_name})
    %{store: store_name}
  end

  describe "execute/3" do
    test "executes a flow with default options", %{store: store} do
      handler = fn signal, state ->
        {Signal.emit(:processed, "#{signal.data}_done"), state}
      end

      signal = Signal.new(:test, "data")
      {:ok, result, _state} = Runtime.execute([handler], signal, store_name: store)

      assert result.type == :processed
      assert result.data == "data_done"
    end

    test "maintains state between handlers", %{store: store} do
      handlers = [
        fn signal, state ->
          new_state = Map.put(state, :count, 1)
          {Signal.emit(:step1, signal.data), new_state}
        end,
        fn signal, state ->
          count = Map.get(state, :count, 0)
          {Signal.emit(:step2, "#{signal.data}_#{count}"), state}
        end
      ]

      signal = Signal.new(:test, "data")
      {:ok, result, final_state} = Runtime.execute(handlers, signal, store_name: store)

      assert result.type == :step2
      assert result.data == "data_1"
      assert final_state.count == 1
    end

    test "supports debug mode", %{store: store} do
      handler = fn signal, state ->
        {Signal.emit(:processed, signal.data), state}
      end

      signal = Signal.new(:test, "data")

      {:ok, result, _state} =
        Runtime.execute(
          [handler],
          signal,
          debug: true,
          name: "test_flow",
          store_name: store
        )

      assert result.type == :processed
      assert result.data == "data"
    end
  end

  describe "configure/2" do
    test "creates a reusable flow configuration", %{store: store} do
      handler = fn signal, state ->
        {Signal.emit(:echo, signal.data), state}
      end

      flow = Runtime.configure([handler], name: "echo_flow", store_name: store)
      signal = Signal.new(:test, "message")
      {:ok, result, _state} = flow.(signal)

      assert result.type == :echo
      assert result.data == "message"
    end

    test "preserves options between executions", %{store: store} do
      counter = fn _signal, state ->
        count = Map.get(state, :count, 0) + 1
        {Signal.emit(:count, count), Map.put(state, :count, count)}
      end

      flow = Runtime.configure([counter], store_name: store)

      signal = Signal.new(:inc, nil)
      {:ok, result1, _} = flow.(signal)
      {:ok, result2, _} = flow.(signal)

      assert result1.data == 1
      # State not preserved between calls
      assert result2.data == 1
    end
  end

  describe "configure_stateful/2" do
    test "maintains state between executions", %{store: store} do
      counter = fn _signal, state ->
        count = Map.get(state, :count, 0) + 1
        {Signal.emit(:count, count), Map.put(state, :count, count)}
      end

      store_key = :test_counter
      flow = Runtime.configure_stateful([counter], store_name: store, store_key: store_key)

      signal = Signal.new(:inc, nil)
      {:ok, result1, _} = flow.(signal)
      {:ok, result2, _} = flow.(signal)

      assert result1.data == 1
      # State preserved between calls
      assert result2.data == 2
    end

    test "generates unique store keys when not provided", %{store: store} do
      handler = fn signal, state ->
        {Signal.emit(:echo, signal.data), state}
      end

      flow1 = Runtime.configure_stateful([handler], store_name: store)
      flow2 = Runtime.configure_stateful([handler], store_name: store)

      signal = Signal.new(:test, "data")
      {:ok, result1, _} = flow1.(signal)
      {:ok, result2, _} = flow2.(signal)

      assert result1.type == :echo
      assert result2.type == :echo
      # Different flows don't interfere with each other
      assert result1.meta.trace_id != result2.meta.trace_id
    end

    test "uses provided store prefix", %{store: store} do
      handler = fn _signal, state ->
        count = Map.get(state, :count, 0) + 1
        {Signal.emit(:count, count), Map.put(state, :count, count)}
      end

      flow =
        Runtime.configure_stateful(
          [handler],
          store_name: store,
          store_prefix: "test"
        )

      signal = Signal.new(:inc, nil)
      {:ok, result, _} = flow.(signal)

      assert result.type == :count
      assert result.data == 1
    end
  end
end
