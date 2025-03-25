defmodule Examples.LimitedWorkflow do
  @moduledoc """
  This example demonstrates how to use execution limits in AgentForge.
  
  It shows:
  1. How to set timeout limits
  2. How to collect and analyze execution statistics
  3. How to handle timeouts gracefully
  """
  
  alias AgentForge.{Signal, Flow, ExecutionStats}
  
  def run do
    IO.puts("=== Running Limited Workflow Example ===\n")
    
    # Simple example with timeout
    run_with_timeout()
    
    # Example collecting statistics
    run_with_statistics()
    
    # Example with long-running handler that will timeout
    run_with_timeout_error()
  end
  
  defp run_with_timeout do
    IO.puts("\n--- Basic Example with Timeout ---")
    
    # Define a simple handler
    handler = fn signal, state ->
      IO.puts("Processing signal: #{signal.type} -> #{inspect(signal.data)}")
      Process.sleep(100) # Simulate some work
      {{:emit, Signal.new(:processed, signal.data)}, state}
    end
    
    # Create signal and process with a generous timeout
    signal = Signal.new(:task, "Sample data")
    
    {:ok, result, _state} = Flow.process_with_limits(
      [handler], 
      signal, 
      %{},
      timeout_ms: 5000 # 5 second timeout
    )
    
    IO.puts("Result: #{result.type} -> #{inspect(result.data)}")
  end
  
  defp run_with_statistics do
    IO.puts("\n--- Example with Statistics Collection ---")
    
    # Define handlers that we'll track statistics for
    handlers = [
      # First handler - validate data
      fn signal, state ->
        IO.puts("Validating data...")
        Process.sleep(50) # Simulate validation
        {{:emit, Signal.new(:validated, signal.data)}, state}
      end,
      
      # Second handler - transform data
      fn signal, state ->
        IO.puts("Transforming data...")
        Process.sleep(100) # Simulate transformation
        {{:emit, Signal.new(:transformed, "#{signal.data} (transformed)")}, state}
      end,
      
      # Third handler - finalize
      fn signal, state ->
        IO.puts("Finalizing...")
        Process.sleep(75) # Simulate finalization
        {{:emit, Signal.new(:completed, signal.data)}, state}
      end
    ]
    
    # Create signal and process with statistics
    signal = Signal.new(:input, "Test data")
    
    {:ok, result, _state, stats} = Flow.process_with_limits(
      handlers, 
      signal, 
      %{},
      timeout_ms: 5000,
      return_stats: true # Return stats in the result
    )
    
    IO.puts("Result: #{result.type} -> #{inspect(result.data)}")
    IO.puts("\nExecution Statistics:")
    IO.puts("- Total steps: #{stats.steps}")
    IO.puts("- Elapsed time: #{stats.elapsed_ms}ms")
    IO.puts("- Completed: #{stats.complete}")
  end
  
  defp run_with_timeout_error do
    IO.puts("\n--- Example with Timeout Error ---")
    
    # Define a handler that will take too long
    slow_handler = fn signal, state ->
      IO.puts("Starting long process...")
      # This will exceed our timeout
      Process.sleep(2000)
      {{:emit, Signal.new(:done, signal.data)}, state}
    end
    
    signal = Signal.new(:task, "Important data")
    
    # Process with a short timeout - this should timeout
    result = Flow.process_with_limits(
      [slow_handler], 
      signal, 
      %{},
      timeout_ms: 500 # Only 500ms timeout
    )
    
    case result do
      {:error, error_message, _state} ->
        IO.puts("Error handled gracefully: #{error_message}")
        
      other ->
        IO.puts("Unexpected result: #{inspect(other)}")
    end
    
    # We can still retrieve the execution stats afterwards
    stats = Flow.get_last_execution_stats()
    
    if stats do
      IO.puts("\nTimeout Statistics:")
      IO.puts("- Elapsed time: #{stats.elapsed_ms}ms")
      IO.puts("- Completed: #{stats.complete}")
    else
      IO.puts("\nNo statistics available")
    end
  end
end

# Run the example when this file is executed directly
if Code.ensure_loaded?(IEx) && IEx.started?() do
  # Running in IEx, let the user decide when to run
  IO.puts("Run Examples.LimitedWorkflow.run() to execute the example")
else
  # Running as a script, execute immediately
  Examples.LimitedWorkflow.run()
end
