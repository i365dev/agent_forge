defmodule AgentForge.Config do
  @moduledoc """
  Provides configuration parsing for declarative workflows.
  Supports loading workflows from YAML or JSON.
  """

  alias AgentForge.{Flow, Primitives, Tools, Signal, Runtime}

  @doc """
  Loads a workflow from a YAML or JSON string.
  Returns a flow function that can be executed.

  ## Examples

      iex> config = \"\"\"
      ...> flow:
      ...>   - type: transform
      ...>     fn: upcase
      ...>   - type: branch
      ...>     condition: "String.length(data) > 5"
      ...>     then:
      ...>       - type: tool
      ...>         name: notify
      ...>     else:
      ...>       - type: tool
      ...>         name: log
      ...> \"\"\"
      iex> flow = AgentForge.Config.load_from_string(config)
      iex> is_function(flow, 1)
      true
  """
  def load_from_string(content) when is_binary(content) do
    case parse_config(content) do
      {:ok, config} ->
        case build_flow(config) do
          {:ok, handlers} ->
            # Return an executable flow function
            Runtime.configure(handlers)

          {:error, reason} ->
            fn _signal -> {:error, reason} end
        end

      {:error, reason} ->
        fn _signal -> {:error, reason} end
    end
  end

  @doc """
  Loads a workflow from a YAML or JSON file.
  Returns a flow function that can be executed.

  ## Examples

      iex> flow = AgentForge.Config.load_from_file("test/fixtures/simple_workflow.yaml")
      iex> is_function(flow, 1)
      true
  """
  def load_from_file(file_path) when is_binary(file_path) do
    with {:ok, content} <- File.read(file_path),
         flow <- load_from_string(content) do
      flow
    else
      {:error, reason} ->
        fn _signal -> {:error, "Failed to read file: #{inspect(reason)}"} end
    end
  end

  # Private functions

  defp parse_config(content) do
    cond do
      String.starts_with?(String.trim(content), "{") ->
        # Looks like JSON
        parse_json(content)

      true ->
        # Assume YAML
        parse_yaml(content)
    end
  end

  defp parse_yaml(yaml_content) do
    case YamlElixir.read_from_string(yaml_content) do
      {:ok, config} -> {:ok, config}
      {:error, reason} -> {:error, "YAML parsing error: #{inspect(reason)}"}
    end
  end

  defp parse_json(json_content) do
    case Jason.decode(json_content) do
      {:ok, config} -> {:ok, config}
      {:error, reason} -> {:error, "JSON parsing error: #{inspect(reason)}"}
    end
  end

  defp build_flow(config) do
    case config["flow"] || config[:flow] do
      nil ->
        {:error, "Missing flow definition in configuration"}

      steps when is_list(steps) ->
        handlers =
          try do
            Enum.map(steps, &build_step/1)
          rescue
            e -> {:error, "Error building flow: #{Exception.message(e)}"}
          end

        case handlers do
          {:error, reason} -> {:error, reason}
          _ -> {:ok, handlers}
        end

      _ ->
        {:error, "Flow must be a list of steps"}
    end
  end

  defp build_step(step) do
    type = step["type"] || step[:type]

    case type do
      "transform" -> build_transform_step(step)
      "branch" -> build_branch_step(step)
      "tool" -> build_tool_step(step)
      "loop" -> build_loop_step(step)
      "sequence" -> build_sequence_step(step)
      nil -> raise "Missing step type"
      _ -> raise "Unknown step type: #{type}"
    end
  end

  defp build_transform_step(step) do
    fn_def = step["fn"] || step[:fn]

    transform_fn =
      case fn_def do
        "upcase" ->
          &String.upcase/1

        "downcase" ->
          &String.downcase/1

        "reverse" ->
          &String.reverse/1

        custom when is_binary(custom) ->
          # Safely handle custom function strings
          fn data ->
            try do
              {result, _} = Code.eval_string(custom, data: data)
              result
            rescue
              e -> raise "Transform evaluation error: #{Exception.message(e)}"
            end
          end

        _ ->
          raise "Invalid transform function: #{inspect(fn_def)}"
      end

    Primitives.transform(transform_fn)
  end

  defp build_branch_step(step) do
    condition_def = step["condition"] || step[:condition]
    then_steps = step["then"] || step[:then] || []
    else_steps = step["else"] || step[:else] || []

    # Build condition function
    condition = build_condition(condition_def)

    # Build sub-flows
    then_flow = Enum.map(then_steps, &build_step/1)
    else_flow = Enum.map(else_steps, &build_step/1)

    Primitives.branch(condition, then_flow, else_flow)
  end

  defp build_condition(condition_def) when is_binary(condition_def) do
    # Create function for simple conditions
    fn signal, state ->
      try do
        bindings = [
          data: signal.data,
          signal: signal,
          state: state,
          # Allow String module in conditions
          String: String
        ]

        {result, _} = Code.eval_string(condition_def, bindings)

        if is_boolean(result) do
          result
        else
          raise "Condition must return a boolean, got: #{inspect(result)}"
        end
      rescue
        e ->
          # Handle condition errors as false but log the error
          IO.warn("Condition evaluation error: #{Exception.message(e)}")
          false
      end
    end
  end

  defp build_condition(condition_def) when is_function(condition_def, 2), do: condition_def
  defp build_condition(_), do: fn _, _ -> true end

  defp build_tool_step(step) do
    tool_name = step["name"] || step[:name]

    if is_nil(tool_name) or not is_binary(tool_name) do
      raise "Tool step requires a valid name, got: #{inspect(tool_name)}"
    end

    # Use tool execution API
    Tools.execute(tool_name)
  end

  defp build_loop_step(step) do
    # Prefix with _ since it's not used yet
    _items_def = step["items"] || step[:items]
    action_steps = step["action"] || step[:action] || []

    unless is_list(action_steps) do
      raise "Loop action must be a list of steps, got: #{inspect(action_steps)}"
    end

    # Build handler for single item
    item_handler = fn item, state ->
      # Create signal for each item using current item as data
      item_signal = Signal.new(:loop_item, item)

      # Build and execute sub-flow
      handlers = Enum.map(action_steps, &build_step/1)

      case Flow.process(handlers, item_signal, state) do
        {:ok, result, new_state} -> {{:emit, result}, new_state}
        {:error, reason} -> {{:emit, Signal.new(:error, reason)}, state}
      end
    end

    Primitives.loop(item_handler)
  end

  defp build_sequence_step(step) do
    steps = step["steps"] || step[:steps] || []

    unless is_list(steps) do
      raise "Sequence must be a list of steps, got: #{inspect(steps)}"
    end

    # Build and compose all substeps
    handlers = Enum.map(steps, &build_step/1)

    Primitives.sequence(handlers)
  end
end
