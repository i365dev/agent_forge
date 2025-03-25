# Execution Limits

AgentForge provides execution limits to ensure that your workflows behave predictably and efficiently. This guide covers the use of timeouts and execution statistics to monitor and control your flows.

## Table of Contents

- [Overview](#overview)
- [Timeout Limits](#timeout-limits)
- [Execution Statistics](#execution-statistics)
- [Error Handling](#error-handling)
- [API Reference](#api-reference)
- [Examples](#examples)

## Overview

When running complex workflows, especially those interacting with external systems or performing intensive computations, it's important to have safeguards against:

- Infinite loops
- Long-running operations
- Resource exhaustion
- Unresponsive services

AgentForge's execution limits provide these safeguards through timeouts and detailed statistics tracking.

## Timeout Limits

### Setting Timeouts

You can set a timeout in milliseconds for any flow processing:

```elixir
# Create a handler
handler = fn signal, state ->
  # Long-running operation...
  {{:emit, Signal.new(:done, result)}, state}
end

# Apply a 5-second timeout
{:ok, result, state} = AgentForge.process_with_limits(
  [handler], 
  signal, 
  %{}, 
  timeout_ms: 5000  # 5 second timeout
)
```

If the processing exceeds the timeout, it will be terminated and return an error:

```elixir
{:error, "Flow execution timed out after 5000ms", state}
```

### Default Timeout

If not specified, the default timeout is 30 seconds (30,000 ms). You can adjust this based on your application's needs.

## Execution Statistics

AgentForge can collect detailed statistics about flow execution, including:

- Number of steps executed
- Total execution time
- Completion status
- Result of execution

### Collecting Statistics

Statistics are collected by default but not returned unless requested:

```elixir
# Get statistics in the result
{:ok, result, state, stats} = AgentForge.process_with_limits(
  handlers, 
  signal, 
  %{}, 
  return_stats: true
)

# Examine the statistics
IO.inspect(stats.steps)      # Number of steps executed
IO.inspect(stats.elapsed_ms) # Execution time in milliseconds
IO.inspect(stats.complete)   # Whether execution completed normally
```

### Retrieving Last Execution Statistics

Even if you don't request statistics in the return value, you can retrieve them afterward:

```elixir
# Process without requesting statistics in the return
{:ok, result, state} = AgentForge.process_with_limits(handlers, signal, %{})

# Retrieve statistics later
stats = AgentForge.get_last_execution_stats()
```

This is particularly useful for logging and monitoring.

## Error Handling

Execution limits can produce several error scenarios:

### Timeout Errors

When a flow exceeds its time limit:

```elixir
{:error, "Flow execution timed out after 5000ms", state}
```

With statistics:

```elixir
{:error, "Flow execution timed out after 5000ms", state, stats}
```

### Handler Errors

When a handler raises an exception:

```elixir
{:error, "Flow processing error: ...", state}
```

### Handling Errors Gracefully

Always wrap flow execution in appropriate error handling:

```elixir
case AgentForge.process_with_limits(handlers, signal, state, timeout_ms: 5000) do
  {:ok, result, new_state} ->
    # Process completed successfully
    handle_success(result, new_state)
    
  {:error, "Flow execution timed out" <> _, state} ->
    # Handle timeout specifically
    handle_timeout(state)
    
  {:error, error_message, state} ->
    # Handle other errors
    handle_error(error_message, state)
end
```

## API Reference

### `AgentForge.process_with_limits/4`

```elixir
@spec process_with_limits(
  [handler_function], 
  Signal.t(), 
  state_map, 
  options
) :: 
  {:ok, Signal.t(), state_map} | 
  {:ok, Signal.t(), state_map, ExecutionStats.t()} | 
  {:error, String.t(), state_map} | 
  {:error, String.t(), state_map, ExecutionStats.t()}
```

Options:
- `timeout_ms`: Maximum execution time in milliseconds (default: 30000)
- `collect_stats`: Whether to collect execution statistics (default: true)
- `return_stats`: Whether to include statistics in the return value (default: false)
- `store_name`: Name of the store to use for state persistence
- `store_key`: Key within the store to access state

### `AgentForge.get_last_execution_stats/0`

```elixir
@spec get_last_execution_stats() :: ExecutionStats.t() | nil
```

Returns the statistics from the last flow execution or nil if none are available.

## Examples

### Basic Timeout Example

```elixir
# Define a handler that may take too long
potentially_slow_handler = fn signal, state ->
  result = perform_intensive_operation(signal.data)
  {{:emit, Signal.new(:processed, result)}, state}
end

# Process with a timeout
case AgentForge.process_with_limits([potentially_slow_handler], signal, %{}, timeout_ms: 10000) do
  {:ok, result, state} ->
    IO.puts("Completed successfully: #{inspect(result.data)}")
    
  {:error, error_message, _state} ->
    IO.puts("Error: #{error_message}")
end
```

### Collecting Performance Metrics

```elixir
# Process and collect statistics
{:ok, result, _state, stats} = AgentForge.process_with_limits(
  workflow, 
  signal, 
  %{}, 
  return_stats: true
)

# Log performance metrics
Logger.info("Workflow completed in #{stats.elapsed_ms}ms with #{stats.steps} steps")
```

For a complete working example, see [limited_workflow.exs](../examples/limited_workflow.exs) in the examples directory.
