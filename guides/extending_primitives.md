# Extending AgentForge Primitives

This guide explains how to create custom primitives for AgentForge.

## Primitive Structure

A primitive is a function that returns a handler function with the signature:
```elixir
(signal, state) -> {result, new_state}
```

## Creating Custom Primitives

### Basic Template

```elixir
def my_primitive(options) do
  fn signal, state ->
    # Process signal and state
    {{:emit, new_signal}, new_state}
  end
end
```

### Result Types

Your primitive should return one of these result types:

```elixir
{{:emit, signal}, new_state}           # Emit single signal
{{:emit_many, signals}, new_state}     # Emit multiple signals
{{:halt, result}, new_state}           # Stop processing
{{:wait, reason}, new_state}           # Pause processing
{{:error, reason}, state}              # Error condition
{:skip, new_state}                     # Skip further processing
```

## Example: Rate Limiter Primitive

Here's a complete example of a custom primitive that implements rate limiting:

```elixir
defmodule MyPrimitives do
  alias AgentForge.{Signal}

  @doc """
  Creates a rate limiter primitive that controls signal processing rate.

  ## Options

  * `:limit` - Maximum number of signals per interval
  * `:interval` - Time interval in milliseconds
  
  ## Examples

      iex> limiter = rate_limit(limit: 2, interval: 1000)
      iex> signal = Signal.new(:test, "data")
      iex> {{:emit, result}, state} = limiter.(signal, %{})
  """
  def rate_limit(opts) do
    limit = Keyword.get(opts, :limit, 10)
    interval = Keyword.get(opts, :interval, 1000)

    fn signal, state ->
      current_time = System.monotonic_time(:millisecond)
      window_start = Map.get(state, :window_start, current_time)
      count = Map.get(state, :count, 0)

      cond do
        # New window
        current_time - window_start > interval ->
          new_state = %{
            window_start: current_time,
            count: 1
          }
          {{:emit, signal}, new_state}

        # Within limit
        count < limit ->
          new_state = %{
            window_start: window_start,
            count: count + 1
          }
          {{:emit, signal}, new_state}

        # Rate limit exceeded
        true ->
          wait_time = window_start + interval - current_time
          {{:wait, "Rate limit exceeded, retry in #{wait_time}ms"}, state}
      end
    end
  end
end
```

## Testing Custom Primitives

Follow these testing patterns:

```elixir
defmodule MyPrimitivesTest do
  use ExUnit.Case
  alias AgentForge.Signal

  describe "rate_limit/1" do
    test "allows signals within limit" do
      limiter = MyPrimitives.rate_limit(limit: 2, interval: 1000)
      signal = Signal.new(:test, "data")
      state = %{}

      # First signal
      {{:emit, result1}, state1} = limiter.(signal, state)
      assert result1.type == :test

      # Second signal
      {{:emit, result2}, _state2} = limiter.(signal, state1)
      assert result2.type == :test
    end

    test "rate limits excessive signals" do
      limiter = MyPrimitives.rate_limit(limit: 1, interval: 1000)
      signal = Signal.new(:test, "data")
      state = %{}

      {{:emit, _}, state1} = limiter.(signal, state)
      {{:wait, reason}, _} = limiter.(signal, state1)

      assert reason =~ "Rate limit exceeded"
    end
  end
end
```

## Best Practices

1. **Documentation**
   - Use `@moduledoc` and `@doc` with examples
   - Document all options
   - Include usage patterns

2. **Options Handling**
   - Use `Keyword.get/3` for optional parameters
   - Validate options early
   - Provide sensible defaults

3. **State Management**
   - Keep state immutable
   - Document state structure
   - Clean up state when needed

4. **Error Handling**
   - Use clear error messages
   - Return `{:error, reason}` for recoverable errors
   - Raise only for programming errors

5. **Testing**
   - Test happy paths
   - Test error conditions
   - Test state transitions
   - Test edge cases

## Integration

To use your custom primitives:

```elixir
defmodule MyWorkflow do
  alias AgentForge.{Flow, Signal}
  alias MyPrimitives

  def run do
    # Create rate-limited workflow
    workflow = [
      MyPrimitives.rate_limit(limit: 10, interval: 1000),
      &process_data/2
    ]

    # Execute
    signal = Signal.new(:start, "data")
    Flow.process(workflow, signal, %{})
  end

  defp process_data(signal, state) do
    # ... processing logic ...
  end
end
```

## Advanced Patterns

### Composing Primitives

```elixir
def rate_limited_transform(transform_fn, rate_opts) do
  fn signal, state ->
    limiter = rate_limit(rate_opts)
    transformer = transform(transform_fn)

    case limiter.(signal, state) do
      {{:emit, limited_signal}, new_state} ->
        transformer.(limited_signal, new_state)
      other -> other
    end
  end
end
```

### Stateful Primitives

```elixir
def with_cache(ttl_ms) do
  fn signal, state ->
    cache = Map.get(state, :cache, %{})
    key = "#{signal.type}:#{inspect(signal.data)}"
    current_time = System.monotonic_time(:millisecond)

    case cache do
      %{^key => {value, expires_at}} when current_time < expires_at ->
        {{:emit, Signal.new(:cached, value)}, state}
      _ ->
        # Process and cache
        new_cache = Map.put(cache, key, {
          signal.data,
          current_time + ttl_ms
        })
        {{:emit, signal}, Map.put(state, :cache, new_cache)}
    end
  end
end
```

## Next Steps

- Review core primitives source code for patterns
- Contribute primitives back to the community
- Share your implementations in discussions
