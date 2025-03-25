defmodule AgentForge.FlowLimitsTest do
  use ExUnit.Case

  alias AgentForge.Flow
  alias AgentForge.Signal

  describe "process_with_limits/4" do
    test "processes a simple flow without timeout" do
      signal = Signal.new(:test, "data")
      handler = fn sig, state -> {{:emit, Signal.new(:echo, sig.data)}, state} end

      {:ok, result, state} = Flow.process_with_limits([handler], signal, %{})

      assert result.type == :echo
      assert result.data == "data"
      assert state == %{}
    end

    test "enforces timeout for infinite loops" do
      signal = Signal.new(:start, "data")

      # Create an infinite loop handler that always emits the same signal
      infinite_loop = fn signal, state ->
        # Add a small delay to ensure timeout works
        Process.sleep(100)
        {{:emit, signal}, state}
      end

      # Should terminate after timeout
      result = Flow.process_with_limits([infinite_loop], signal, %{}, timeout_ms: 300)

      # Verify we got an error
      assert {:error, error_msg, final_state} = result
      assert error_msg =~ "timed out"
      # State should be preserved
      assert final_state == %{}
    end

    test "handles normal termination" do
      signal = Signal.new(:test, "data")

      # This handler will terminate after 3 steps
      counter_handler = fn signal, state ->
        counter = Map.get(state, :counter, 0) + 1
        new_state = Map.put(state, :counter, counter)

        if counter >= 3 do
          # Terminate after 3 steps
          {{:halt, "done after #{counter} steps"}, new_state}
        else
          # Continue, but update type to show progress
          {{:emit, Signal.new(:"step_#{counter}", signal.data)}, new_state}
        end
      end

      # Should complete normally
      {:ok, result, final_state} = Flow.process_with_limits([counter_handler], signal, %{})

      assert result == "done after 3 steps"
      assert final_state.counter == 3
    end

    test "handles multiple signal emissions" do
      signal = Signal.new(:test, "data")

      # Handler that emits multiple signals
      multi_emit = fn _signal, state ->
        signals = [
          Signal.new(:first, "one"),
          Signal.new(:second, "two"),
          Signal.new(:third, "three")
        ]

        {{:emit_many, signals}, state}
      end

      {:ok, result, _state} = Flow.process_with_limits([multi_emit], signal, %{})

      # Should continue with the last signal
      assert result.type == :third
      assert result.data == "three"
    end

    test "handles errors in handlers" do
      signal = Signal.new(:test, "data")

      # Create a handler that returns an error
      error_handler = fn _signal, state ->
        {{:error, "Handler error"}, state}
      end

      # Should catch and properly handle the error
      {:error, error_msg, state} = Flow.process_with_limits([error_handler], signal, %{})

      assert error_msg == "Handler error"
      # State should be preserved
      assert state == %{}
    end

    test "respects handler skip response" do
      signal = Signal.new(:test, "data")

      # Create a skipping handler
      skip_handler = fn _signal, state -> {:skip, state} end

      {:ok, result, state} = Flow.process_with_limits([skip_handler], signal, %{})

      assert result == signal
      assert state == %{}
    end
  end
end
