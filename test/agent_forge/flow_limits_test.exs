defmodule AgentForge.FlowLimitsTest do
  use ExUnit.Case

  alias AgentForge.Flow
  alias AgentForge.Signal
  alias AgentForge.ExecutionStats

  describe "process_with_limits/4" do
    test "processes a simple flow without limits" do
      signal = Signal.new(:test, "data")
      handler = fn sig, state -> {{:emit, Signal.new(:echo, sig.data)}, state} end

      {:ok, result, state} = Flow.process_with_limits([handler], signal, %{})

      assert result.type == :echo
      assert result.data == "data"
      assert state == %{}
    end

    test "enforces maximum step limit" do
      # Create an infinite loop handler
      infinite_loop = fn signal, state ->
        {{:emit, signal}, state}
      end

      signal = Signal.new(:start, "data")

      # Should terminate after reaching max steps
      {:error, error} = Flow.process_with_limits([infinite_loop], signal, %{}, max_steps: 5)

      assert error =~ "exceeded maximum steps"
      assert error =~ "reached 5"
    end

    test "enforces timeout limit" do
      # Create a slow handler
      slow_handler = fn signal, state ->
        Process.sleep(50)  # delay for 50ms
        {{:emit, signal}, state}
      end

      signal = Signal.new(:start, "data")

      # Should timeout after 10ms
      {:error, error} = Flow.process_with_limits([slow_handler], signal, %{}, timeout: 10)

      assert error =~ "timed out"
    end

    test "returns statistics when requested" do
      signal = Signal.new(:test, "data")
      handler = fn sig, state -> {{:emit, Signal.new(:echo, sig.data)}, state} end

      {:ok, result, state, stats} = Flow.process_with_limits([handler], signal, %{}, return_stats: true)

      assert result.type == :echo
      assert result.data == "data"
      assert state == %{}
      assert %ExecutionStats{} = stats
      assert stats.steps == 1
      assert stats.signal_types == %{test: 1}
      assert stats.complete == true
    end

    test "returns error statistics when requested" do
      signal = Signal.new(:test, "data")
      error_handler = fn _sig, _state -> {{:error, "test error"}, %{}} end

      {:error, reason, stats} = Flow.process_with_limits([error_handler], signal, %{}, return_stats: true)

      assert reason == "test error"
      assert %ExecutionStats{} = stats
      assert stats.steps == 1
      assert stats.result == {:error, "test error"}
      assert stats.complete == true
    end

    test "can disable statistics collection" do
      signal = Signal.new(:test, "data")
      handler = fn sig, state -> {{:emit, Signal.new(:echo, sig.data)}, state} end

      {:ok, result, state} = Flow.process_with_limits([handler], signal, %{}, collect_stats: false)

      assert result.type == :echo
      assert result.data == "data"
      assert state == %{}
      assert Flow.get_last_execution_stats() == nil
    end

    test "handles skip with limits" do
      signal = Signal.new(:test, "data")
      handlers = [
        fn _sig, state -> {:skip, state} end,
        fn _sig, _state -> raise "Should not reach this" end
      ]

      {:ok, nil, state} = Flow.process_with_limits(handlers, signal, %{}, max_steps: 1)
      assert state == %{}
    end

    test "preserves state on limit errors" do
      signal = Signal.new(:test, "data")
      initial_state = %{important: "data"}

      infinite_loop = fn sig, state ->
        {{:emit, sig}, Map.put(state, :counter, Map.get(state, :counter, 0) + 1)}
      end

      {:error, error} = Flow.process_with_limits(
        [infinite_loop],
        signal,
        initial_state,
        max_steps: 3
      )

      assert error =~ "exceeded maximum steps"
      assert Flow.get_last_execution_stats().max_state_size == 2
    end
  end
end
