# AgentForge Core Concepts

This guide explains the fundamental concepts of the AgentForge framework and how they work together to create dynamic workflows.

## Core Components

### 1. Signals

Signals are the fundamental unit of communication in AgentForge. They carry both data and metadata about events or actions in the system.

```elixir
# Basic signal creation
signal = Signal.new(:user_action, %{id: 1, data: "example"})

# Signal structure
%{
  type: :user_action,
  data: %{id: 1, data: "example"},
  meta: %{timestamp: ~U[2025-03-22 10:00:00Z]}
}
```

### 2. Handlers

Handlers are functions that process signals and maintain state. They follow a consistent interface:

```elixir
# Handler function signature
(signal, state) -> {result, new_state}

# Example handler
def process_user(signal, state) do
  new_state = Map.put(state, :last_user, signal.data)
  {Signal.emit(:user_processed, signal.data), new_state}
end
```

### 3. Flows

Flows compose multiple handlers into processing pipelines. They manage the execution order and error handling.

```elixir
# Creating a flow
flow = [
  &validate_user/2,
  &enrich_user_data/2,
  &save_user/2
]

# Processing a signal through the flow
{:ok, result, final_state} = Flow.process(flow, signal, initial_state)
```

### 4. Primitives

Primitives are building blocks for creating handlers. AgentForge provides several core primitives:

#### Branch Primitive
Conditionally executes different flows based on a condition:

```elixir
branch = Primitives.branch(
  fn signal, _ -> signal.data.age >= 18 end,
  adult_flow,
  minor_flow
)
```

#### Transform Primitive
Modifies signal data:

```elixir
transform = Primitives.transform(fn data ->
  Map.put(data, :processed_at, DateTime.utc_now())
end)
```

#### Loop Primitive
Iterates over items in signal data:

```elixir
loop = Primitives.loop(fn item, state ->
  {Signal.emit(:item_processed, item), state}
end)
```

#### Wait Primitive
Pauses execution until a condition is met:

```elixir
wait = Primitives.wait(
  fn _, state -> state.resource_ready end,
  timeout: 5000
)
```

#### Notify Primitive
Sends notifications through configured channels:

```elixir
notify = Primitives.notify(
  [:console, :webhook],
  format: &("User #{&1.name} registered")
)
```

### 5. State Management

State is maintained throughout the workflow execution:

```elixir
# Initial state
state = %{counter: 0}

# Handler updating state
def count_signal(signal, state) do
  new_state = Map.update(state, :counter, 1, & &1 + 1)
  {signal, new_state}
end
```

## Common Patterns

### 1. Signal Chaining

```elixir
def process_order(signal, state) do
  with {:ok, validated} <- validate_order(signal.data),
       {:ok, enriched} <- enrich_order(validated),
       {:ok, saved} <- save_order(enriched) do
    {Signal.emit(:order_processed, saved), state}
  else
    {:error, reason} -> {Signal.emit(:order_failed, reason), state}
  end
end
```

### 2. State Accumulation

```elixir
def aggregate_totals(signal, state) do
  total = Map.get(state, :total, 0) + signal.data.amount
  {signal, Map.put(state, :total, total)}
end
```

### 3. Conditional Processing

```elixir
def route_request(signal, state) do
  case signal.data.priority do
    :high -> {Signal.emit(:urgent, signal.data), state}
    :low -> {Signal.emit(:routine, signal.data), state}
  end
end
```

## Configuration-based Workflows

AgentForge supports defining workflows through configuration:

```yaml
name: user_registration
steps:
  - name: validate_input
    type: transform
    config:
      validate:
        - field: email
          required: true
  - name: process_user
    type: branch
    config:
      condition: "age >= 18"
      then_flow: adult_flow
      else_flow: minor_flow
```

## Error Handling

AgentForge provides several ways to handle errors:

1. Return tagged tuples:
```elixir
{:error, reason} -> {Signal.emit(:error, reason), state}
```

2. Use rescue in transforms:
```elixir
Primitives.transform(fn data ->
  # ... risky operation ...
rescue
  e -> raise "Processing failed: #{Exception.message(e)}"
end)
```

3. Handle errors in flows:
```elixir
case Flow.process(workflow, signal, state) do
  {:ok, result, final_state} -> handle_success(result)
  {:error, reason} -> handle_error(reason)
end
```

## Best Practices

1. Keep handlers small and focused
2. Use appropriate primitives for common patterns
3. Maintain immutable state
4. Handle errors at appropriate levels
5. Use clear signal types and meaningful data
6. Document handlers and flows
7. Test different execution paths

## Next Steps

- Check out the examples in the `examples/` directory
- Read the primitive-specific guides
- Review the test files for more usage patterns
- See the CONTRIBUTING.md file for development guidelines
