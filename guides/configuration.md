# Configuring AgentForge Workflows

This guide explains how to define workflows using configuration files.

## YAML Configuration

AgentForge supports defining workflows in YAML format:

```yaml
name: order_processing
description: Handles incoming orders

steps:
  - name: validate_order
    type: transform
    config:
      validate:
        - field: order_id
          required: true
        - field: amount
          type: number
          min: 0

  - name: enrich_order
    type: transform
    config:
      add_fields:
        - timestamp: now()
        - status: pending

  - name: route_order
    type: branch
    config:
      condition: "amount >= 1000"
      then_flow: high_value_flow
      else_flow: standard_flow

flows:
  high_value_flow:
    - name: review_order
      type: notify
      config:
        channels: [console, webhook]
        message: "High-value order {order_id} requires review"

  standard_flow:
    - name: auto_process
      type: transform
      config:
        process:
          status: approved
```

## Configuration Structure

### 1. Workflow Metadata

```yaml
name: workflow_name           # Required: Unique workflow identifier
description: workflow_desc    # Optional: Description of the workflow
version: 1.0                 # Optional: Workflow version
```

### 2. Steps Configuration

Each step must define:
- `name`: Unique identifier within the workflow
- `type`: Primitive type to use
- `config`: Type-specific configuration

### 3. Available Step Types

#### Transform
```yaml
- name: step_name
  type: transform
  config:
    validate:              # Field validation
      - field: field_name
        required: true
        type: string
    add_fields:           # Add new fields
      - field_name: value
    remove_fields:        # Remove fields
      - field_name
```

#### Branch
```yaml
- name: step_name
  type: branch
  config:
    condition: "expression"    # Condition to evaluate
    then_flow: flow_name      # Flow to use if true
    else_flow: flow_name      # Flow to use if false
```

#### Loop
```yaml
- name: step_name
  type: loop
  config:
    iterator: "items"         # Field containing items
    item_handler: flow_name   # Flow to process each item
```

#### Wait
```yaml
- name: step_name
  type: wait
  config:
    condition: "expression"   # Wait condition
    timeout: 5000            # Timeout in milliseconds
    retry_interval: 100      # Retry interval
```

#### Notify
```yaml
- name: step_name
  type: notify
  config:
    channels: [console, webhook]
    message: "Template {variable}"
    format: "json"           # Optional format
```

## Using Configuration Files

### 1. Loading Configuration

```elixir
defmodule MyWorkflow do
  alias AgentForge.{Config, Flow}

  def run(data) do
    # Load workflow configuration
    {:ok, workflow} = Config.load_file("workflows/order_processing.yaml")
    
    # Create initial signal
    signal = Signal.new(:order, data)
    
    # Execute workflow
    Flow.process(workflow.steps, signal, %{})
  end
end
```

### 2. Dynamic Configuration

You can modify configuration at runtime:

```elixir
def run(data, opts) do
  {:ok, workflow} = Config.load_file("workflows/base.yaml")
  
  # Modify configuration
  workflow = Config.update_in(workflow, [:steps, :notify, :config], fn config ->
    Map.put(config, :channels, opts.channels)
  end)
  
  Flow.process(workflow.steps, signal, %{})
end
```

## Configuration Best Practices

1. **Organization**
   - Group related workflows in directories
   - Use clear, descriptive names
   - Include version information

2. **Reusability**
   - Define common flows separately
   - Use templates for repeated patterns
   - Share configurations across similar workflows

3. **Maintainability**
   - Document configuration files
   - Use consistent naming conventions
   - Keep configurations focused

4. **Validation**
   - Validate configurations at load time
   - Include schema definitions
   - Test configuration variations

## Example Configurations

### 1. Data Validation
```yaml
name: data_validation
steps:
  - name: validate_user
    type: transform
    config:
      validate:
        - field: email
          required: true
          pattern: "^[^@]+@[^@]+$"
        - field: age
          type: number
          min: 18
```

### 2. Async Processing
```yaml
name: async_process
steps:
  - name: start_job
    type: transform
    config:
      trigger_async: true
  - name: wait_completion
    type: wait
    config:
      condition: "job_completed"
      timeout: 30000
```

### 3. Conditional Flows
```yaml
name: conditional_process
steps:
  - name: check_data
    type: branch
    config:
      condition: "valid_data"
      then_flow: process_flow
      else_flow: error_flow
```

## Debugging Configuration

1. **Logging**
```yaml
name: debug_workflow
steps:
  - name: debug_step
    type: notify
    config:
      channels: [console]
      message: "Processing: {data}"
      log_level: debug
```

2. **Testing Configurations**
```elixir
def test_config do
  {:ok, workflow} = Config.load_file("test/fixtures/workflow.yaml")
  
  # Validate configuration
  assert workflow.name == "test_workflow"
  assert length(workflow.steps) > 0
  
  # Test with sample data
  signal = Signal.new(:test, sample_data)
  {:ok, result, _} = Flow.process(workflow.steps, signal, %{})
end
```

## Next Steps

1. Review example workflows in `examples/workflows/`
2. Try modifying existing configurations
3. Create custom configurations
4. Learn about [extending primitives](extending_primitives.md)
