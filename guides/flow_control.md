# Flow Control

This guide explains the advanced flow control features in AgentForge that allow you to build dynamic and responsive workflows.

## Table of Contents

- [Overview](#overview)
- [Signal Strategies](#signal-strategies)
  - [Forward Strategy](#forward-strategy)
  - [Transform Strategy](#transform-strategy)
  - [Restart Strategy](#restart-strategy)
- [Skip Handling](#skip-handling)
- [Branching Logic](#branching-logic)
- [Execution Limits](#execution-limits)
- [Examples](#examples)

## Overview

AgentForge's flow control system allows you to define how signals move through handlers and how the processing chain responds to different scenarios. These features give you fine-grained control over your workflow execution.

## Signal Strategies

Signal strategies determine how signals are passed between handlers in a flow. AgentForge supports three primary strategies:

### Forward Strategy

The forward strategy (default) passes signals unchanged to the next handler in the chain. This is the simplest form of signal propagation.

```elixir
# Using forward strategy (default behavior)
Flow.process_with_limits(handlers, signal, state, signal_strategy: :forward)
```

Example flow with forward strategy:

```elixir
handlers = [
  # First handler emits a signal
  fn signal, state ->
    {{:emit, Signal.new(:validated, signal.data)}, state}
  end,
  
  # Second handler receives the exact signal emitted by the first
  fn signal, state ->
    IO.puts("Received signal type: #{signal.type}")
    {{:emit, Signal.new(:done, signal.data)}, state}
  end
]

# Process with forward strategy
Flow.process_with_limits(handlers, signal, state)
```

### Transform Strategy

The transform strategy allows you to modify signals before they reach the next handler. This is useful for pre-processing or standardizing signals.

```elixir
# Define a transformation function
transform_fn = fn signal -> 
  # Add a timestamp to the signal data
  updated_data = Map.put(signal.data, :processed_at, DateTime.utc_now())
  # Return a new signal with the updated data
  Map.put(signal, :data, updated_data)
end

# Use transform strategy
Flow.process_with_limits(handlers, signal, state, 
  signal_strategy: :transform,
  transform_fn: transform_fn
)
```

Example flow with transform strategy:

```elixir
transform_fn = fn signal -> 
  # Convert all data strings to uppercase
  updated_data = 
    if is_binary(signal.data) do
      String.upcase(signal.data)
    else
      signal.data
    end
  
  Map.put(signal, :data, updated_data)
end

handlers = [
  # First handler
  fn signal, state ->
    {{:emit, Signal.new(:processed, "hello world")}, state}
  end,
  
  # Second handler receives transformed signal
  # The data will be "HELLO WORLD" instead of "hello world"
  fn signal, state ->
    IO.puts("Received data: #{signal.data}")
    {{:emit, Signal.new(:done, signal.data)}, state}
  end
]

# Process with transform strategy
Flow.process_with_limits(handlers, signal, state,
  signal_strategy: :transform,
  transform_fn: transform_fn
)
```

### Restart Strategy

The restart strategy is particularly powerful for creating iterative workflows. When a handler emits a signal, the flow restarts from the beginning with the new signal rather than continuing to the next handler.

```elixir
# Using restart strategy
Flow.process_with_limits(handlers, signal, state, 
  signal_strategy: :restart,
  max_steps: 10  # Prevent infinite loops
)
```

Example flow with restart strategy:

```elixir
handlers = [
  # Check if processing is complete
  fn signal, state ->
    if Map.get(state, :counter, 0) >= 3 do
      # We're done after 3 iterations
      {{:emit, Signal.new(:done, state.counter)}, state}
    else
      # Continue processing
      {{:emit, Signal.new(:continue, "processing")}, state}
    end
  end,
  
  # Increment counter and restart the flow
  fn signal, state ->
    case signal.type do
      :continue ->
        new_counter = Map.get(state, :counter, 0) + 1
        new_state = Map.put(state, :counter, new_counter)
        IO.puts("Iteration: #{new_counter}")
        
        # This will restart the flow from the first handler
        {{:emit, Signal.new(:check, new_counter)}, new_state}
        
      :done ->
        # Pass through the done signal
        {signal, state}
    end
  end
]

# Process with restart strategy
Flow.process_with_limits(handlers, Signal.new(:check, 0), %{},
  signal_strategy: :restart,
  max_steps: 10  # Set a maximum to prevent infinite loops
)
```

## Skip Handling

By default, when a handler returns `:skip`, the flow processing halts. However, you can configure the flow to continue processing with subsequent handlers after a skip.

```elixir
# Default behavior - skip halts the flow
Flow.process_with_limits(handlers, signal, state, continue_on_skip: false)

# Alternative - continue processing after a skip
Flow.process_with_limits(handlers, signal, state, continue_on_skip: true)
```

Example with continue_on_skip:

```elixir
handlers = [
  # This handler might skip
  fn signal, state ->
    if String.length(signal.data) < 10 do
      IO.puts("Skipping - data too short")
      {:skip, state}
    else
      IO.puts("Processing data")
      {{:emit, Signal.new(:processed, signal.data)}, state}
    end
  end,
  
  # With continue_on_skip: true, this handler will execute even after a skip
  fn signal, state ->
    IO.puts("Second handler running")
    {{:emit, Signal.new(:done, "completed")}, state}
  end
]

# Process with continue_on_skip
Flow.process_with_limits(handlers, signal, state, continue_on_skip: true)
```

## Branching Logic

Handlers can implement conditional branching using the `:branch` return type, which allows the flow to take different paths based on a condition.

```elixir
# Handler with branching logic
branch_handler = fn signal, state ->
  condition = String.length(signal.data) > 5
  
  {:branch, condition,
   # True branch state - use this state if condition is true
   Map.put(state, :path, "long_path"),
   # False branch state - use this state if condition is false
   Map.put(state, :path, "short_path")
  }
end
```

Example flow with branching:

```elixir
handlers = [
  # Branching handler
  fn signal, state ->
    condition = String.length(signal.data) > 5
    
    {:branch, condition,
     # True branch - for long strings
     Map.put(state, :path, "long_path"),
     # False branch - for short strings
     Map.put(state, :path, "short_path")
    }
  end,
  
  # This handler receives the state from the branch
  fn signal, state ->
    IO.puts("Taking the #{state.path}")
    {{:emit, Signal.new(:done, state.path)}, state}
  end
]

# Process flow with branching
Flow.process_with_limits(handlers, signal, %{})
```

## Execution Limits

To prevent infinite loops, especially when using the restart strategy, always set appropriate execution limits:

```elixir
# Set maximum number of steps
Flow.process_with_limits(handlers, signal, state, max_steps: 100)

# Set maximum execution time
Flow.process_with_limits(handlers, signal, state, timeout_ms: 5000)
```

## Examples

For complete examples of these flow control techniques, see the following example files:

```elixir
# Run the enhanced flow control example
mix run examples/enhanced_flow_control.exs

# Run the limited workflow example
mix run examples/limited_workflow.exs
```

These examples demonstrate practical applications of the flow control features in realistic workflows.
