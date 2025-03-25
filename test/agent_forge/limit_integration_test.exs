defmodule AgentForge.LimitIntegrationTest do
  use ExUnit.Case

  alias AgentForge.Store

  setup do
    store_name = :"store_#{System.unique_integer()}"
    start_supervised!({Store, name: store_name})
    %{store: store_name}
  end

  describe "process_with_limits integration" do
    test "top-level API correctly applies limits" do
      # Create a slow handler
      slow_handler = fn signal, state ->
        # delay for 100ms
        Process.sleep(100)
        {{:emit, signal}, state}
      end

      signal = AgentForge.new_signal(:test, "data")

      {:error, error, _state} =
        AgentForge.process_with_limits([slow_handler], signal, %{}, timeout_ms: 50)

      assert error =~ "timed out"

      # Check stats are available
      stats = AgentForge.get_last_execution_stats()
      assert stats != nil
    end

    test "full flow with state persistence", %{store: store} do
      # Create a counter handler
      counter = fn _signal, state ->
        count = Map.get(state, :count, 0) + 1
        {{:emit, AgentForge.new_signal(:count, count)}, Map.put(state, :count, count)}
      end

      signal = AgentForge.new_signal(:test, "data")

      # First execution - use direct call to Runtime.execute_with_limits for store integration
      {:ok, result1, state1, stats1} =
        AgentForge.Runtime.execute_with_limits(
          [counter],
          signal,
          store_name: store,
          store_key: :counter_test,
          return_stats: true
        )

      assert result1.data == 1
      assert state1.count == 1
      assert stats1.steps >= 1

      # Second execution with stored state - should retrieve state from the store
      {:ok, result2, state2, stats2} =
        AgentForge.Runtime.execute_with_limits(
          [counter],
          signal,
          store_name: store,
          store_key: :counter_test,
          return_stats: true
        )

      # Counter increased
      assert result2.data == 2
      assert state2.count == 2
      assert stats2.steps >= 1
    end
  end
end
