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

    test "enforces timeout limit using timeout_ms parameter" do
      # Create a slow handler
      slow_handler = fn signal, state ->
        # delay for 100ms
        Process.sleep(100)
        {{:emit, signal}, state}
      end

      signal = Signal.new(:test, "data")

      # Should timeout after 50ms
      {:error, error, state} = Flow.process_with_limits([slow_handler], signal, %{}, timeout_ms: 50)

      assert error =~ "timed out after 50ms"
      assert state == %{}
    end

    test "returns statistics when requested" do
      signal = Signal.new(:test, "data")
      handler = fn sig, state -> {{:emit, Signal.new(:echo, sig.data)}, state} end
      
      {:ok, result, state, stats} = Flow.process_with_limits([handler], signal, %{}, return_stats: true)
      
      assert result.type == :echo
      assert result.data == "data"
      assert state == %{}
      assert %ExecutionStats{} = stats
      assert stats.steps >= 1
      assert stats.complete == true
    end

    test "returns statistics on timeout" do
      signal = Signal.new(:test, "data")
      
      # Create a slow handler
      slow_handler = fn signal, state ->
        Process.sleep(100)  # delay for 100ms
        {{:emit, signal}, state}
      end
      
      {:error, error, state, stats} = 
        Flow.process_with_limits([slow_handler], signal, %{}, timeout_ms: 50, return_stats: true)
      
      assert error =~ "timed out"
      assert state == %{}
      assert %ExecutionStats{} = stats
      # The actual implementation marks stats as complete even on timeout
      # since statistics collection itself completes successfully
      assert stats.complete == true
      assert {:error, _} = stats.result
    end

    test "can disable statistics collection" do
      signal = Signal.new(:test, "data")
      handler = fn sig, state -> {{:emit, Signal.new(:echo, sig.data)}, state} end
      
      # Clear any previous stats
      Process.put(:"$agent_forge_last_execution_stats", nil)
      
      {:ok, result, state} = 
        Flow.process_with_limits([handler], signal, %{}, collect_stats: false)
      
      assert result.type == :echo
      assert result.data == "data"
      assert state == %{}
      assert Flow.get_last_execution_stats() == nil  # No stats collected
    end

    test "saves statistics to process when return_stats is false" do
      signal = Signal.new(:test, "data")
      handler = fn sig, state -> {{:emit, Signal.new(:echo, sig.data)}, state} end
      
      # Clear any previous stats
      Process.put(:"$agent_forge_last_execution_stats", nil)
      
      {:ok, result, _} = Flow.process_with_limits([handler], signal, %{})
      
      assert result.type == :echo
      assert Flow.get_last_execution_stats() != nil
      assert Flow.get_last_execution_stats().steps >= 1
    end

    test "handles emit_many signal type" do
      signal = Signal.new(:test, "data")
      
      # Handler that emits multiple signals
      multi_handler = fn _sig, state ->
        signals = [
          Signal.new(:first, "one"),
          Signal.new(:second, "two"),
          Signal.new(:third, "three")
        ]
        {{:emit_many, signals}, state}
      end
      
      # Second handler to verify which signal is passed from emit_many
      verifier = fn sig, state ->
        # Should get the last signal from emit_many
        assert sig.type == :third
        assert sig.data == "three"
        {{:emit, sig}, state}
      end
      
      {:ok, result, _} = Flow.process_with_limits([multi_handler, verifier], signal, %{})
      
      assert result.type == :third
      assert result.data == "three"
    end

    test "handles alternative halt pattern" do
      signal = Signal.new(:test, "data")
      
      # Handler with alternative halt pattern
      alt_halt = fn _sig, _state ->
        {:halt, "halted result"}
      end
      
      {:ok, result, _state} = Flow.process_with_limits([alt_halt], signal, %{})
      
      assert result == "halted result"
    end

    test "handles alternative halt pattern with state" do
      signal = Signal.new(:test, "data")
      
      # Handler with second alternative halt pattern
      alt_halt2 = fn _sig, state ->
        {{:halt, "halted with state"}, state}
      end
      
      {:ok, result, _state} = Flow.process_with_limits([alt_halt2], signal, %{})
      
      assert result == "halted with state"
    end
  end
end
