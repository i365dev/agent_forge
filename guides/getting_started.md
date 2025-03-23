# Getting Started with AgentForge

This guide will help you get up and running with AgentForge quickly.

## Installation

Add AgentForge to your mix.exs dependencies:

```elixir
def deps do
  [
    {:agent_forge, "~> 0.1.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Quick Start Example

Let's create a simple workflow that processes user registration:

```elixir
defmodule UserRegistration do
  alias AgentForge.{Flow, Signal, Primitives}

  def run do
    # 1. Define validation transform
    validate = Primitives.transform(fn user ->
      cond do
        is_nil(user.email) -> raise "Email is required"
        String.length(user.password) < 8 -> raise "Password too short"
        true -> user
      end
    end)

    # 2. Define data enrichment
    enrich = Primitives.transform(fn user ->
      Map.merge(user, %{
        created_at: DateTime.utc_now(),
        status: :active
      })
    end)

    # 3. Define notification
    notify = Primitives.notify(
      [:console],
      format: &("New user registered: #{&1.email}")
    )

    # 4. Compose workflow
    workflow = [validate, enrich, notify]

    # 5. Process a registration
    user = %{email: "user@example.com", password: "secret123"}
    signal = Signal.new(:registration, user)
    
    case Flow.process(workflow, signal, %{}) do
      {:ok, result, _state} ->
        IO.puts("Registration successful!")
        IO.inspect(result)
      
      {:error, reason} ->
        IO.puts("Registration failed: #{reason}")
    end
  end
end

# Run the example
UserRegistration.run()
```

## Core Concepts

### 1. Signals

Signals are messages that flow through your system:

```elixir
# Create a signal with a type and data
signal = Signal.new(:user_action, %{id: 1, data: "example"})
```

### 2. Primitives

Primitives are building blocks for creating handlers:

```elixir
# Transform primitive
transform = Primitives.transform(&String.upcase/1)

# Branch primitive
branch = Primitives.branch(
  fn signal, _ -> signal.data.age >= 18 end,
  adult_handlers,
  minor_handlers
)

# Loop primitive
loop = Primitives.loop(fn item, state ->
  {Signal.emit(:processed, item), state}
end)

# Wait primitive
wait = Primitives.wait(
  fn _, state -> state.ready end,
  timeout: 5000
)

# Notify primitive
notify = Primitives.notify(
  [:console],
  format: &("Event: #{&1}")
)
```

### 3. Flows

Flows combine handlers into pipelines:

```elixir
workflow = [
  &validate/2,
  &process/2,
  &notify/2
]

{:ok, result, state} = Flow.process(workflow, signal, initial_state)
```

## Common Patterns

### Error Handling

```elixir
# In transforms
transform = Primitives.transform(fn data ->
  # ... operation that might fail ...
rescue
  e -> raise "Processing failed: #{Exception.message(e)}"
end)

# In flows
case Flow.process(workflow, signal, state) do
  {:ok, result, state} -> handle_success(result)
  {:error, reason} -> handle_error(reason)
end
```

### State Management

```elixir
# Initialize state
state = %{counter: 0}

# Update state in handler
def count(signal, state) do
  new_state = Map.update(state, :counter, 1, & &1 + 1)
  {signal, new_state}
end
```

## Configuration-based Workflows

AgentForge supports defining workflows in YAML:

```yaml
name: registration
steps:
  - name: validate
    type: transform
    config:
      validate:
        - field: email
          required: true
        - field: password
          min_length: 8
  
  - name: process
    type: notify
    config:
      channels: [console]
      message: "New user: {email}"
```

## Next Steps

1. Read the [Core Concepts](core_concepts.md) guide for deeper understanding
2. Check out the [examples/](../examples/) directory for more examples
3. Learn about [extending primitives](extending_primitives.md)
4. Review the [configuration guide](configuration.md)

## Help and Support

- Report issues on GitHub
- Join the discussion in our community channels
- Check the [documentation](https://hexdocs.pm/agent_forge) for detailed API references
