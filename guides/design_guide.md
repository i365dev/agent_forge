# AgentForge Design Philosophy & Architecture Guide

## Introduction

AgentForge is a lightweight, signal-driven workflow framework designed for building flexible and maintainable data processing pipelines. This guide articulates AgentForge's architectural focus, design principles, and recommendations for extending its functionality.

## Core Focus & Design Philosophy

AgentForge is built on the following key principles:

1. **Simplicity First**: Maintain a minimal, clean codebase that's easy to understand and extend
2. **Signal-Driven Architecture**: Base all operations on immutable signals passing through handler chains
3. **Composable Primitives**: Provide fundamental building blocks that can be combined into complex workflows
4. **State Management**: Support clean, predictable state transitions throughout workflow execution
5. **Execution Control**: Provide mechanisms to control and monitor workflow execution

The framework is designed to excel at workflow orchestration - the coordination, sequencing, and conditional execution of processing steps - while intentionally delegating certain responsibilities to the application layer or specialized libraries.

## What Belongs in the Core Framework

AgentForge's core should remain focused on these fundamental capabilities:

### 1. Signal Processing
- Signal creation, transformation, and emission
- Metadata handling and correlation
- Type-based routing

### 2. Flow Composition
- Handler chaining and execution
- Error propagation and handling
- Execution statistics and monitoring

### 3. Core Primitives
- Branch: Conditional execution
- Transform: Data modification
- Loop: Iterative processing
- Sequence: Ordered execution
- Notify (basic): Simple notification outputs
- Wait: Condition-based pausing

### 4. Configuration Loading
- Configuration-driven workflow definition
- YAML/JSON parsing and validation
- Dynamic flow generation

### 5. Execution Control
- Timeout limitations
- Execution statistics
- Runtime state inspection

## What Belongs at the Application Layer

The following concerns are better implemented at the application layer:

### 1. Scheduling & Timing
- Periodic task execution
- Cron-style scheduling
- Job queuing and prioritization

**Rationale**: Scheduling systems require complex state persistence, error recovery, and distributed coordination that would significantly increase framework complexity. Elixir's ecosystem already provides excellent solutions like Quantum and Oban.

### 2. Data Source Integration
- Database connectors
- API clients
- File system operations
- Streaming data sources

**Rationale**: Different applications have vastly different data source requirements. Embedding specific connectors would add unnecessary dependencies and maintenance burden.

### 3. External Service Integration
- LLM API clients
- Authentication handling
- Rate limiting and retries
- Service-specific error handling

**Rationale**: These integrations evolve rapidly, have diverse configuration requirements, and are typically specific to particular use cases.

### 4. Advanced Notification Systems
- Email delivery
- SMS messaging
- Chat platform integration
- Notification templating

**Rationale**: While basic notification is a core primitive, delivery mechanisms involve complex dependencies and configuration that vary significantly between applications.

## Integration Patterns

To integrate these application-layer concerns with AgentForge, we recommend the following patterns:

### 1. Tool-Based Integration

Register external functionality as tools:

```elixir
# Register an HTTP client tool
Tools.register("http_get", fn config ->
  HTTPoison.get!(config["url"], config["headers"] || [])
  |> Map.get(:body)
  |> Jason.decode!()
end)

# Register an LLM tool
Tools.register("analyze_with_llm", fn input ->
  OpenAI.chat_completion(
    model: "gpt-4",
    messages: [%{role: "user", content: "Analyze: #{input}"}]
  )
  |> Map.get(:choices)
  |> List.first()
  |> Map.get(:message)
  |> Map.get(:content)
end)
```

### 2. Configuration-Driven Integration

Define external integrations in workflow configuration:

```yaml
# workflow.yaml
flow:
  - type: tool
    name: http_get
    config:
      url: "https://api.example.com/data"
  - type: transform
    fn: "process_data"
  - type: tool
    name: analyze_with_llm
```

### 3. Scheduler-Based Triggering

Use external schedulers to trigger AgentForge workflows:

```elixir
# In application code
config :your_app, YourApp.Scheduler,
  jobs: [
    {"0 */1 * * *", fn -> 
      signal = Signal.new(:scheduled_run, %{timestamp: DateTime.utc_now()})
      workflow = load_workflow_from_config("workflows/market_analysis.yaml")
      AgentForge.process_with_limits(workflow, signal, %{}, timeout_ms: 60000)
    end}
  ]
```

## Best Practices

### 1. Keep the Core Framework Thin

- Focus on the essential orchestration capabilities
- Resist adding dependencies for specialized functionality
- Prioritize extensibility over built-in features

### 2. Use Composition Over Configuration

- Compose small, focused handlers rather than complex, configurable ones
- Allow behavior to emerge from composition rather than parameterization
- Build reusable handler libraries at the application level

### 3. Develop Standard Patterns for Common Needs

- Create and share reference implementations for common integration patterns
- Document best practices for specific use cases
- Provide examples rather than built-in solutions

### 4. Consider Extensibility Through Plugins

For commonly needed functionality that doesn't belong in the core, consider a plugin architecture that allows:

- Registration of custom primitives
- Extension of existing primitives
- Addition of new tool types
- Configuration of framework behavior

## Conclusion

AgentForge's strength lies in its focused approach to workflow orchestration. By maintaining a clear separation of concerns between the core framework and application-specific functionality, we ensure AgentForge remains lightweight, maintainable, and adaptable to diverse use cases.

The framework should provide the essential building blocks for workflow orchestration while empowering developers to integrate with specialized tools and services at the application layer, creating a powerful ecosystem without bloating the core framework.
