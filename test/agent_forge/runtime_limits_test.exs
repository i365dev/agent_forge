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
    test "executes a flow with default limits", %{store: store} do
      handler = fn signal, state ->
        {{:emit, Signal.new(:echo, signal.data)}, state}
      end

      signal = Signal.new(:test, "data")

      {:ok, result, _} =
        Runtime.execute_with_limits(
          [handler],
          signal,
          store_name: store
        )

      assert result.type == :echo
      assert result.data == "data"
    end

    test "enforces timeout_ms limit", %{store: store} do
      # Create a slow handler
      slow_handler = fn signal, state ->
        # delay for 100ms
        Process.sleep(100)
        {{:emit, signal}, state}
      end

      signal = Signal.new(:start, "data")

      # Should timeout after 50ms
      {:error, error, _state} =
        Runtime.execute_with_limits(
          [slow_handler],
          signal,
          store_name: store,
          timeout_ms: 50
        )

      assert error =~ "timed out"
    end

    test "preserves state across executions", %{store: store} do
      # Handler that counts executions
      counter = fn _signal, state ->
        count = Map.get(state, :count, 0) + 1
        {{:emit, Signal.new(:count, count)}, Map.put(state, :count, count)}
      end

      signal = Signal.new(:start, "count")

      # First execution
      {:ok, _, state1} =
        Runtime.execute_with_limits(
          [counter],
          signal,
          store_name: store,
          store_key: :test_state
        )

      assert state1.count == 1

      # Second execution should use stored state
      {:ok, result2, state2} =
        Runtime.execute_with_limits(
          [counter],
          signal,
          store_name: store,
          store_key: :test_state
        )

      assert state2.count == 2
      assert result2.data == 2
    end

    test "returns statistics when requested", %{store: store} do
      handler = fn signal, state ->
        {{:emit, Signal.new(:echo, signal.data)}, state}
      end

      signal = Signal.new(:test, "data")

      {:ok, result, _state, stats} =
        Runtime.execute_with_limits(
          [handler],
          signal,
          store_name: store,
          return_stats: true
        )

      assert result.type == :echo
      assert result.data == "data"
      assert %ExecutionStats{} = stats
      assert stats.steps >= 1
      assert stats.complete == true
    end

    test "returns statistics on timeout", %{store: store} do
      # Create a slow handler
      slow_handler = fn signal, state ->
        # delay for 100ms
        Process.sleep(100)
        {{:emit, signal}, state}
      end

      signal = Signal.new(:test, "data")

      {:error, error, _state, stats} =
        Runtime.execute_with_limits(
          [slow_handler],
          signal,
          store_name: store,
          timeout_ms: 50,
          return_stats: true
        )

      assert error =~ "timed out"
      assert %ExecutionStats{} = stats
      # The actual implementation marks stats as complete even on timeout
      # since statistics collection itself completes successfully
      assert stats.complete == true
      assert {:error, _} = stats.result
    end

    test "handles flow errors with statistics", %{store: store} do
      error_handler = fn _signal, _state ->
        {{:error, "test error"}, %{}}
      end

      signal = Signal.new(:test, "data")

      {:error, reason, state, stats} =
        Runtime.execute_with_limits(
          [error_handler],
          signal,
          store_name: store,
          return_stats: true
        )

      assert reason == "test error"
      assert state == %{}
      assert %ExecutionStats{} = stats
      assert stats.steps >= 1
      assert stats.result == {:error, "test error"}
    end

    test "supports disabling statistics", %{store: store} do
      handler = fn signal, state ->
        {{:emit, Signal.new(:echo, signal.data)}, state}
      end

      signal = Signal.new(:test, "data")

      # Clear any previous stats
      Process.put(:"$agent_forge_last_execution_stats", nil)

      {:ok, result, _state} =
        Runtime.execute_with_limits(
          [handler],
          signal,
          store_name: store,
          collect_stats: false
        )

      assert result.type == :echo
      assert result.data == "data"
      assert Runtime.get_last_execution_stats() == nil
    end

    test "combines debug tracing with execution limits", %{store: store} do
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
          timeout_ms: 5000
        )

      assert result.type == :echo
      assert result.data == "data"
    end

    test "preserves state on timeout", %{store: store} do
      # Create a handler that updates state but is slow
      slow_handler = fn signal, state ->
        # delay for 100ms
        Process.sleep(100)
        count = Map.get(state, :count, 0) + 1
        {{:emit, signal}, Map.put(state, :count, count)}
      end

      signal = Signal.new(:test, "data")

      {:error, error, _state} =
        Runtime.execute_with_limits(
          [slow_handler],
          signal,
          store_name: store,
          store_key: :timeout_test,
          timeout_ms: 50
        )

      assert error =~ "timed out"

      # Verify the store wasn't corrupted
      {:ok, stored_state} = Store.get(store, :timeout_test)
      # Initial state should be preserved
      assert stored_state == %{}
    end

    test "preserves initial state when return_stats is true", %{store: store} do
      # Initial state to use
      initial_state = %{counter: 5, important: "data"}
      
      # Set up the store with initial state
      :ok = Store.put(store, :test_state, initial_state)
      
      handler = fn signal, state ->
        new_state = Map.update(state, :counter, 1, &(&1 + 1))
        {{:emit, Signal.new(:echo, signal.data)}, new_state}
      end
      
      signal = Signal.new(:test, "data")
      
      {:ok, _result, final_state, stats} =
        Runtime.execute_with_limits(
          [handler],
          signal,
          store_name: store,
          store_key: :test_state,
          return_stats: true
        )
      
      # Check that the state was properly updated
      assert final_state.counter == 6
      assert final_state.important == "data"
      
      # Check that stats were collected
      assert %ExecutionStats{} = stats
      assert stats.complete == true
      
      # Verify the store was updated correctly
      {:ok, stored_state} = Store.get(store, :test_state)
      assert stored_state.counter == 6
    end
    
    test "supports custom initial state", %{store: store} do
      # Create a handler that accesses custom_value from state
      handler = fn _signal, state ->
        custom_value = Map.get(state, :custom_value, "default")
        {{:emit, Signal.new(:echo, custom_value)}, state}
      end
      
      # Set up the initial state in the store directly
      initial_state = %{custom_value: "custom data"}
      :ok = Store.put(store, :custom_state, initial_state)
      
      signal = Signal.new(:test, "data")
      
      {:ok, result, final_state} =
        Runtime.execute_with_limits(
          [handler],
          signal,
          store_name: store,
          store_key: :custom_state
          # We don't need to pass initial_state here since we've set it in the store
        )
      
      assert result.data == "custom data"
      assert final_state.custom_value == "custom data"
      
      # Verify the store was updated correctly
      {:ok, stored_state} = Store.get(store, :custom_state)
      assert stored_state.custom_value == "custom data"
    end
  end
end
