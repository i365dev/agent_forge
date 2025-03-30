#!/usr/bin/env elixir

# Enhanced Flow Control Example
#
# This example demonstrates the enhanced flow control features in AgentForge:
# 1. continue_on_skip - Continue processing when a handler skips
# 2. signal_strategy - Control how emitted signals are handled
# 3. branching - Conditional processing paths
# 4. function flow - Using function-based workflows
#
# To run: mix run examples/enhanced_flow_control.exs

defmodule Examples.EnhancedFlowControl do
  @moduledoc """
   This example demonstrates enhanced flow control features in AgentForge.

   It shows:
   1. How to use continue_on_skip to proceed after a skip result
   2. How to use different signal strategies (forward, transform, restart)
   3. How to implement conditional branching in workflows
   4. How to use function-based workflows
  """

  alias AgentForge.{Signal, Flow}
  require Logger

  def run do
    IO.puts("=== Running Enhanced Flow Control Examples ===\n")

    # Example of continue_on_skip option
    run_skip_example()

    # Example of signal strategies
    run_signal_strategies()

    # Example of conditional branching
    run_branching_example()

    # Example of function-based workflow
    run_function_flow()

    IO.puts("\n=== Examples Complete ===")
  end

  defp run_skip_example do
    IO.puts("\n--- Example: continue_on_skip ---")

    # Create test handlers
    skip_handler = fn _signal, state ->
      IO.puts("Skip handler called - normally would halt chain")
      {:skip, Map.put(state, :skip_handler_called, true)}
    end

    next_handler = fn _signal, state ->
      IO.puts("Next handler called - will only run if continue_on_skip is true")

      {{:emit, Signal.new(:processed, "processed data")},
       Map.put(state, :next_handler_called, true)}
    end

    # Run with default settings (continue_on_skip = false)
    signal = Signal.new(:test, "test data")

    {result_type, _result, state} =
      Flow.process_with_limits([skip_handler, next_handler], signal, %{})

    IO.puts("Default result: #{result_type}, State: #{inspect(state)}")
    IO.puts("Note: next_handler was NOT called because skip halted the chain")

    # Run with continue_on_skip = true
    {result_type, _result, state} =
      Flow.process_with_limits(
        [skip_handler, next_handler],
        signal,
        %{},
        continue_on_skip: true
      )

    IO.puts("With continue_on_skip: #{result_type}, State: #{inspect(state)}")
    IO.puts("Note: next_handler WAS called because continue_on_skip was true")
  end

  defp run_signal_strategies do
    IO.puts("\n--- Example: signal strategies ---")

    # Create handlers for signal strategy testing
    emit_handler = fn signal, state ->
      new_signal = Signal.new(:transformed, "#{signal.data} - transformed")
      IO.puts("Emit handler creating new signal: #{inspect(new_signal.type)}")
      {{:emit, new_signal}, state}
    end

    logging_handler = fn signal, state ->
      IO.puts("Logging handler received: #{inspect(signal.type)} - #{inspect(signal.data)}")
      {:skip, state}
    end

    # With forward strategy (default)
    IO.puts("\nWith :forward strategy (default):")

    {:ok, result, _state} =
      Flow.process_with_limits(
        [emit_handler, logging_handler],
        Signal.new(:start, "start data"),
        %{},
        signal_strategy: :forward
      )

    IO.puts("Result: #{inspect(result)}")

    # With transform strategy
    IO.puts("\nWith :transform strategy:")

    transform_fn = fn signal ->
      transformed_data = String.upcase(signal.data)
      IO.puts("Transforming signal data to: #{transformed_data}")
      Map.put(signal, :data, transformed_data)
    end

    {:ok, result, _state} =
      Flow.process_with_limits(
        [emit_handler, logging_handler],
        Signal.new(:start, "start data"),
        %{},
        signal_strategy: :transform,
        transform_fn: transform_fn
      )

    IO.puts("Result: #{inspect(result)}")

    # With restart strategy and safeguards
    IO.puts("\nWith :restart strategy:")

    restart_handlers = [
      # First handler with visit counter to prevent infinite loops
      fn _signal, state ->
        visits = Map.get(state, :visit_count, 0)

        case visits do
          0 ->
            IO.puts("First pass - emit restart signal")
            # First visit - emit a restart signal
            {{:emit, Signal.new(:restarted, "restarted data")},
             Map.put(state, :visit_count, visits + 1)}

          1 ->
            IO.puts("Second pass - emit final signal")
            # Second visit - emit a final signal
            {{:emit, Signal.new(:final, "final data")}, Map.put(state, :visit_count, visits + 1)}

          _ ->
            IO.puts("Final pass - halting with result")
            # Third or later visit - halt with result
            {{:halt, "Completed after #{visits} iterations"}, state}
        end
      end,

      # Second handler just logs signal
      fn signal, state ->
        IO.puts("Second handler received: #{inspect(signal.type)}")
        {:skip, state}
      end
    ]

    # Process with restart strategy and explicit step limit
    {:ok, result, state} =
      Flow.process_with_limits(
        restart_handlers,
        Signal.new(:start, "start data"),
        %{},
        signal_strategy: :restart,
        # Explicit step limit as safety measure
        max_steps: 10,
        # Short timeout as additional safety
        timeout_ms: 5000
      )

    IO.puts("Result: #{inspect(result)}")
    IO.puts("Final state: #{inspect(state)}")
  end

  defp run_branching_example do
    IO.puts("\n--- Example: branching ---")

    branch_handlers = [
      # First handler evaluates condition and branches
      fn signal, state ->
        # Use signal data to determine branching condition
        condition = String.length(signal.data) > 5
        IO.puts("Branching based on condition: #{condition}")

        {
          :branch,
          condition,
          # True state (condition is true)
          Map.put(state, :branch, "long_string"),
          # False state (condition is false)
          Map.put(state, :branch, "short_string")
        }
      end,

      # Second handler processes based on branch taken
      fn _signal, state ->
        branch_value = Map.get(state, :branch)
        IO.puts("Branch taken: #{branch_value}")

        # Create a new signal with the branch data
        {{:emit, Signal.new(:branched, branch_value)}, state}
      end
    ]

    # Test with a long string (condition = true)
    {:ok, result, _state} =
      Flow.process(branch_handlers, Signal.new(:branch, "long test string"), %{})

    IO.puts("Result with long string: #{inspect(result)}")

    # Test with a short string (condition = false)
    {:ok, result, _state} = Flow.process(branch_handlers, Signal.new(:branch, "short"), %{})
    IO.puts("Result with short string: #{inspect(result)}")
  end

  defp run_function_flow do
    IO.puts("\n--- Example: function flow ---")

    # Define a function flow
    function_flow = fn signal, state ->
      IO.puts("Function flow processing: #{inspect(signal.type)} - #{inspect(signal.data)}")

      # Process different signal types
      case signal.type do
        :start ->
          # Emit a new signal
          new_signal = Signal.new(:processing, "processing #{signal.data}")
          {:emit, new_signal, state}

        :processing ->
          # Calculate result based on data length
          result =
            if String.length(signal.data) > 15 do
              "long processing result"
            else
              "short processing result"
            end

          # Halt processing with result
          {:halt, result, Map.put(state, :processed, true)}

        _ ->
          # Skip unknown signal types
          {:skip, state}
      end
    end

    # Run function flow
    {:ok, result, state} =
      Flow.process_function_flow(
        function_flow,
        Signal.new(:start, "function flow test"),
        %{}
      )

    IO.puts("Function flow result: #{inspect(result)}")
    IO.puts("Function flow state: #{inspect(state)}")

    # Process different signal type directly
    {:ok, result, state} =
      Flow.process_function_flow(
        function_flow,
        Signal.new(:processing, "direct processing"),
        %{}
      )

    IO.puts("Direct processing result: #{inspect(result)}")
    IO.puts("Direct processing state: #{inspect(state)}")
  end
end

# Run the examples
Examples.EnhancedFlowControl.run()
