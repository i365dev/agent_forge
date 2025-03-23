# Configuration-based Workflow Example
#
# This example demonstrates how to define and run workflows using YAML configuration.
# See examples/workflows/sample.yaml for the workflow definition.
#
# To run: elixir examples/config_workflow.exs

Code.require_file("../lib/agent_forge.ex")
Code.require_file("../lib/agent_forge/signal.ex")
Code.require_file("../lib/agent_forge/flow.ex")
Code.require_file("../lib/agent_forge/primitives.ex")
Code.require_file("../lib/agent_forge/config.ex")

defmodule ConfigWorkflow do
  alias AgentForge.{Flow, Signal, Primitives}

  def validate_field(data, field, rules) do
    value = Map.get(data, field)
    cond do
      rules.required && is_nil(value) ->
        {:error, "#{field} is required"}
      rules.type == "number" && not is_number(value) ->
        {:error, "#{field} must be a number"}
      rules.min && value < rules.min ->
        {:error, "#{field} must be at least #{rules.min}"}
      true ->
        {:ok, value}
    end
  end

  def create_validation_transform(config) do
    Primitives.transform(fn data ->
      Enum.reduce_while(config.validate, data, fn rule, acc ->
        case validate_field(acc, rule.field, rule) do
          {:ok, _} -> {:cont, acc}
          {:error, reason} -> {:halt, raise(reason)}
        end
      end)
    end)
  end

  def create_enrichment_transform(config) do
    Primitives.transform(fn data ->
      Enum.reduce(config.add_fields, data, fn
        %{timestamp: "now()"}, acc ->
          Map.put(acc, :timestamp, DateTime.utc_now())
        field, acc ->
          Map.merge(acc, field)
      end)
    end)
  end

  def create_branch(config, flows) do
    condition = case config.condition do
      "age >= 18" ->
        fn signal, _ -> signal.data.age >= 18 end
    end

    then_flow = Map.get(flows, config.then_flow)
    else_flow = Map.get(flows, config.else_flow)

    Primitives.branch(condition, then_flow, else_flow)
  end

  def create_notification(config) do
    format_fn = fn data ->
      config.message
      |> String.replace("{name}", data.name)
      |> String.replace("{age}", to_string(data.age))
    end

    Primitives.notify(config.channels, format: format_fn)
  end

  def create_handler(step, flows) do
    case step.type do
      "transform" when step.name == "validate_input" ->
        create_validation_transform(step.config)
      "transform" when step.name == "enrich_data" ->
        create_enrichment_transform(step.config)
      "branch" ->
        create_branch(step.config, flows)
      "notify" ->
        create_notification(step.config)
    end
  end

  def load_workflow(path) do
    # In a real implementation, this would use a proper YAML parser
    # For this example, we'll use the sample workflow directly
    %{
      "steps" => [
        %{
          "name" => "validate_input",
          "type" => "transform",
          "config" => %{
            "validate" => [
              %{"field" => "name", "required" => true},
              %{"field" => "age", "type" => "number", "min" => 0}
            ]
          }
        },
        %{
          "name" => "enrich_data",
          "type" => "transform",
          "config" => %{
            "add_fields" => [
              %{"timestamp" => "now()"},
              %{"processed" => true}
            ]
          }
        },
        %{
          "name" => "check_age",
          "type" => "branch",
          "config" => %{
            "condition" => "age >= 18",
            "then_flow" => "adult_flow",
            "else_flow" => "minor_flow"
          }
        }
      ],
      "flows" => %{
        "adult_flow" => [
          %{
            "name" => "process_adult",
            "type" => "notify",
            "config" => %{
              "channels" => ["console"],
              "message" => "Processing adult user: {name}"
            }
          }
        ],
        "minor_flow" => [
          %{
            "name" => "process_minor",
            "type" => "notify",
            "config" => %{
              "channels" => ["console"],
              "message" => "Cannot process minor: {name}",
              "notify_guardian" => true
            }
          }
        ]
      }
    }
  end

  def run do
    # Load workflow configuration
    workflow = load_workflow("examples/workflows/sample.yaml")

    # Create handlers from configuration
    handlers = Enum.map(workflow["steps"], & create_handler(&1, workflow["flows"]))

    # Test data
    test_cases = [
      %{name: "John Doe", age: 25},
      %{name: "Jane Smith", age: 15},
      %{name: nil, age: 20},
      %{name: "Invalid", age: -1}
    ]

    # Process test cases
    Enum.each(test_cases, fn data ->
      IO.puts("\nProcessing: #{inspect(data)}")

      signal = Signal.new(:user_data, data)
      state = %{}

      case Flow.process(handlers, signal, state) do
        {:ok, result, _} ->
          IO.puts("Success: #{inspect(result)}")
        {:error, reason} ->
          IO.puts("Error: #{reason}")
      end
    end)
  end
end

# Run the example
ConfigWorkflow.run()
