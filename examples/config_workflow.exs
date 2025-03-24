# Configuration-based Workflow Example
#
# This example demonstrates how to define and run workflows using YAML configuration.
# See examples/workflows/sample.yaml for the workflow definition.
#
# To run: elixir examples/config_workflow.exs

Code.require_file("lib/agent_forge.ex")
Code.require_file("lib/agent_forge/signal.ex")
Code.require_file("lib/agent_forge/flow.ex")
Code.require_file("lib/agent_forge/primitives.ex")
Code.require_file("lib/agent_forge/config.ex")

defmodule ConfigWorkflow do
  alias AgentForge.{Flow, Signal, Primitives}

  def validate_field(data, field, rules) do
    value = Map.get(data, String.to_atom(field))
    cond do
      rules["required"] && is_nil(value) ->
        {:error, "#{field} is required"}
      rules["type"] == "number" && not is_number(value) ->
        {:error, "#{field} must be a number"}
      rules["min"] && value < rules["min"] ->
        {:error, "#{field} must be at least #{rules["min"]}"}
      true ->
        {:ok, value}
    end
  end

  def create_validation_transform(config) do
    fn signal, state ->
      result = Enum.reduce_while(config["validate"], {:ok, signal.data}, fn rule, {:ok, acc} ->
        case validate_field(acc, rule["field"], rule) do
          {:ok, _} ->
            {:cont, {:ok, acc}}
          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)

      case result do
        {:ok, data} ->
          {Signal.emit(:validated, data), state}
        {:error, reason} ->
          {Signal.halt(reason), state}
      end
    end
  end

  def create_enrichment_transform(config) do
    fn signal, state ->
      try do
        enriched_data = Enum.reduce(config["add_fields"], signal.data, fn
          %{"timestamp" => "now()"}, acc ->
            Map.put(acc, :timestamp, DateTime.utc_now())
          field, acc ->
            Map.merge(acc, field)
        end)
        {Signal.emit(:enriched, enriched_data), state}
      rescue
        e in RuntimeError -> {Signal.emit(:error, e.message), state}
      end
    end
  end

  def create_branch(config, flows) do
    condition = case config["condition"] do
      "age >= 18" ->
        fn signal, _ -> Map.get(signal.data, :age) >= 18 end
    end

    then_flow = flows[config["then_flow"]]
    |> Enum.map(fn step -> create_handler(step, flows) end)

    else_flow = flows[config["else_flow"]]
    |> Enum.map(fn step -> create_handler(step, flows) end)

    Primitives.branch(condition, then_flow, else_flow)
  end

  def create_notification(config) do
    fn signal, state ->
      try do
        message = config["message"]
        |> String.replace("{name}", to_string(Map.get(signal.data, :name)))
        |> String.replace("{age}", to_string(Map.get(signal.data, :age)))

        {Signal.emit(:notification, message), state}
      rescue
        e in RuntimeError -> {Signal.emit(:error, e.message), state}
      end
    end
  end

  def create_handler(step, flows) do
    case {step["type"], step["name"]} do
      {"transform", "validate_input"} ->
        create_validation_transform(step["config"])
      {"transform", "enrich_data"} ->
        create_enrichment_transform(step["config"])
      {"branch", _} ->
        create_branch(step["config"], flows)
      {"notify", _} ->
        create_notification(step["config"])
    end
  end

  @doc """
  Load workflow configuration
  """
  def load_workflow(_path) do
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

  def format_error({:validation_error, message}), do: "Validation error: #{message}"
  def format_error({:error, message}) when is_binary(message), do: message
  def format_error({:badmap, message}) when is_binary(message), do: message
  def format_error(reason), do: "Error: #{inspect(reason)}"

  def run do
    # Load workflow configuration from YAML
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

      case process_with_error_handling(handlers, signal, state) do
        {:ok, result} ->
          IO.puts("Success: #{inspect(result)}")
        {:error, reason} ->
          IO.puts("Error: #{reason}")
      end
    end)
  end

  defp process_with_error_handling(handlers, signal, state) do
    case Flow.process(handlers, signal, state) do
      {:ok, result, _} ->
        {:ok, result}
      {:halt, msg, _} ->
        {:error, msg}
      {:error, {:badmap, msg}} ->
        clean_msg = msg
        |> String.replace(~r/Transform error: expected a map got: "/, "")
        |> String.replace(~r/"$/, "")
        {:error, clean_msg}
      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end
end

# Run the example
ConfigWorkflow.run()
