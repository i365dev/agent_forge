defmodule AgentForge.RuntimeLimitsTest do
  use ExUnit.Case

  alias AgentForge.Runtime
  alias AgentForge.Signal
  alias AgentForge.ExecutionStats
  alias AgentForge.Store

  setup do
    # Each test gets a unique store to avoid conflicts
    store_name = :"store_#{System.unique_integer()}"
    start_supervised!({Store, name: store_name})
    %{store: store_name}
  end

  describe "execute_with_limits/3" do
    test "executes a flow with limits", %{store: store} do
      handler = fn signal, state ->
        {{:emit, Signal.new(:echo, signal.data)}, state}
      end

      signal = Signal.new(:test, "data")

      {:ok, result, _} =
        Runtime.execute_with_limits(
          [handler],
          signal,
          store_name: store,
          max_steps: 10
        )

      assert result.type == :echo
      assert result.data == "data"
    end

    test "enforces maximum step limit", %{store: store} do
      # Create an infinite loop handler
      infinite_loop = fn signal, state ->
        {{:emit, signal}, state}
      end

      signal = Signal.new(:start, "data")

      # Should terminate after reaching max steps
      {:error, error} =
        Runtime.execute_with_limits(
          [infinite_loop],
          signal,
          store_name: store,
          max_steps: 5
        )

      assert error =~ "exceeded maximum steps"
    end

    test "preserves state across limited executions", %{store: store} do
      # Handler that counts executions
      counter = fn _signal, state ->
        count = Map.get(state, :count, 0) + 1
        {{:emit, Signal.new(:count, count)}, Map.put(state, :count, count)}
      end

      signal = Signal.new(:start, "count")

      # First execution with limit of 3 steps
      {:ok, _, state1} =
        Runtime.execute_with_limits(
          [counter],
          signal,
          store_name: store,
          store_key: :test_state,
          max_steps: 3
        )

      assert state1.count == 1

      # Second execution should use stored state
      {:ok, result2, state2} =
        Runtime.execute_with_limits(
          [counter],
          signal,
          store_name: store,
          store_key: :test_state,
          max_steps: 3
        )

      assert state2.count == 2
      assert result2.data == 2
    end

    test "returns statistics with limits when requested", %{store: store} do
      handler = fn signal, state ->
        {{:emit, Signal.new(:echo, signal.data)}, state}
      end

      signal = Signal.new(:test, "data")

      {:ok, result, _state, stats} =
        Runtime.execute_with_limits(
          [handler],
          signal,
          store_name: store,
          return_stats: true,
          max_steps: 5
        )

      assert result.type == :echo
      assert result.data == "data"
      assert %ExecutionStats{} = stats
      assert stats.steps == 1
      assert stats.signal_types == %{test: 1}
      assert stats.complete == true
    end

    test "handles flow errors with statistics", %{store: store} do
      error_handler = fn _signal, _state ->
        {{:error, "test error"}, %{}}
      end

      signal = Signal.new(:test, "data")

      {:error, reason, stats} =
        Runtime.execute_with_limits(
          [error_handler],
          signal,
          store_name: store,
          return_stats: true
        )

      assert reason == "test error"
      assert %ExecutionStats{} = stats
      assert stats.steps == 1
      assert stats.result == {:error, "test error"}
    end

    test "supports disabling statistics", %{store: store} do
      handler = fn signal, state ->
        {{:emit, Signal.new(:echo, signal.data)}, state}
      end

      signal = Signal.new(:test, "data")

      {:ok, result, _state} =
        Runtime.execute_with_limits(
          [handler],
          signal,
          store_name: store,
          collect_stats: false
        )

      assert result.type == :echo
      assert result.data == "data"
    end

    test "combines debug tracing with limits", %{store: store} do
      handler = fn signal, state ->
        {{:emit, Signal.new(:echo, signal.data)}, state}
      end

      signal = Signal.new(:test, "data")

      {:ok, result, _state} =
        Runtime.execute_with_limits(
          [handler],
          signal,
          store_name: store,
          debug: true,
          max_steps: 5
        )

      assert result.type == :echo
      assert result.data == "data"
    end

    test "preserves state on timeout", %{store: store} do
      # Create a handler that updates state but is slow
      slow_handler = fn signal, state ->
        # delay for 50ms
        Process.sleep(50)
        count = Map.get(state, :count, 0) + 1
        {{:emit, signal}, Map.put(state, :count, count)}
      end

      signal = Signal.new(:test, "data")

      {:error, error} =
        Runtime.execute_with_limits(
          [slow_handler],
          signal,
          store_name: store,
          store_key: :timeout_test,
          timeout: 10
        )

      assert error =~ "timed out"

      # Verify the store wasn't corrupted
      {:ok, stored_state} = Store.get(store, :timeout_test)
      # Initial state should be preserved
      assert stored_state == %{}
    end
  end
end
