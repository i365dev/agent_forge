# AgentForge

[![CI](https://github.com/i365dev/agent_forge/actions/workflows/ci.yml/badge.svg)](https://github.com/i365dev/agent_forge/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/agent_forge.svg)](https://hex.pm/packages/agent_forge)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/agent_forge)
[![License](https://img.shields.io/hexpm/l/agent_forge.svg)](https://github.com/i365dev/agent_forge/blob/main/LICENSE)

AgentForge is a lightweight, signal-driven workflow framework for Elixir, designed for building flexible and maintainable data processing pipelines.

```mermaid
graph TB
    Signal[Signal] --> Handler[Handler]
    Handler --> Store[Store]
    Handler --> Flow[Flow]
    Flow --> Runtime[Runtime]
```

## Features

- 🔄 **Signal-driven Architecture**: Build workflows around immutable signals
- 🧩 **Composable Primitives**: Core building blocks for common patterns
- 🔀 **Flexible Flows**: Chain handlers into dynamic processing pipelines
- 📦 **State Management**: Track and update workflow state
- ⚡ **Async Support**: Handle asynchronous operations
- 🛠 **Configuration-based**: Define workflows in YAML
- 💪 **Type-safe**: Leverages Elixir's pattern matching

## Quick Start

```elixir
# Add to mix.exs
def deps do
  [
    {:agent_forge, "~> 0.1.0"}
  ]
end

# Run
mix deps.get
```

### Simple Example

```elixir
defmodule Example do
  alias AgentForge.{Flow, Signal, Primitives}

  def run do
    # Define workflow steps
    validate = Primitives.transform(fn data ->
      if data.valid?, do: data, else: raise "Invalid data"
    end)

    process = Primitives.transform(fn data ->
      Map.put(data, :processed, true)
    end)

    notify = Primitives.notify(
      [:console],
      format: &("Processed: #{inspect(&1)}")
    )

    # Compose workflow
    workflow = [validate, process, notify]

    # Execute
    signal = Signal.new(:start, %{valid?: true})
    {:ok, result, _state} = Flow.process(workflow, signal, %{})
    IO.inspect(result)
  end
end
```

## Core Components

### Signals
Immutable messages that flow through the system:
```elixir
signal = Signal.new(:user_action, %{id: 1})
```

### Primitives
Building blocks for common patterns:
- **Branch**: Conditional processing
- **Transform**: Data modification
- **Loop**: Iteration handling
- **Wait**: Async operations
- **Notify**: Event notifications

### Flows
Compose handlers into pipelines:
```elixir
workflow = [&validate/2, &process/2, &notify/2]
```

## Documentation

- [Getting Started Guide](guides/getting_started.md)
- [Core Concepts](guides/core_concepts.md)
- [Contribution Guidelines](CONTRIBUTING.md)

## Examples

- [Data Processing](examples/data_processing.exs): Basic data transformation pipeline
- [Async Workflow](examples/async_workflow.exs): Handling async operations
- [Configuration-based](examples/config_workflow.exs): YAML-defined workflows

## Design Philosophy

AgentForge focuses on:
- **Simplicity**: Clean, understandable codebase
- **Flexibility**: Adaptable to various use cases
- **Maintainability**: Well-documented, tested code
- **Composability**: Build complex flows from simple parts

## Use Cases

- ✅ Data Processing Pipelines
- ✅ Event-driven Workflows
- ✅ Multi-step Validations
- ✅ Async Task Orchestration
- ✅ Business Process Automation

## Development

### Setup

```bash
# Clone the repository
git clone https://github.com/USERNAME/agent_forge.git
cd agent_forge

# Get dependencies
mix deps.get

# Run tests
mix test

# Generate documentation
mix docs
```

### Pre-release Checklist

- [ ] All tests pass (`mix test`)
- [ ] Test coverage is acceptable (`mix coveralls.html` - check coverage/excoveralls.html)
- [ ] Code is formatted (`mix format`)
- [ ] Documentation generates without errors (`mix docs`)
- [ ] Version number is correct in mix.exs
- [ ] CHANGELOG.md is updated
- [ ] GitHub Actions workflows are in place
- [ ] All examples run without errors

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for guidelines.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Run the tests (`mix test`)
4. Commit your changes (`git commit -m 'Add some amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
