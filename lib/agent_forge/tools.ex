defmodule AgentForge.Tools do
  @moduledoc """
  Provides a registry for tools and safe execution environment.
  Tools are registered functions that can be invoked by handlers during flow execution.
  """

  use Agent

  alias AgentForge.Signal

  @doc """
  Starts the tool registry.

  ## Examples

      iex> {:ok, _pid} = AgentForge.Tools.start_link(name: :test_registry)
      iex> AgentForge.Tools.register("uppercase", &String.upcase/1, :test_registry)
      :ok
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(fn -> %{} end, name: name)
  end

  @doc """
  Registers a tool with the given name.
  The tool function should take a single argument (signal data) and return a result.

  ## Examples

      iex> {:ok, _pid} = AgentForge.Tools.start_link(name: :test_registry1)
      iex> AgentForge.Tools.register("uppercase", &String.upcase/1, :test_registry1)
      :ok
      iex> AgentForge.Tools.register("add_one", fn n -> n + 1 end, :test_registry1)
      :ok
  """
  def register(name, tool_fn, registry \\ __MODULE__)
      when is_binary(name) and is_function(tool_fn, 1) do
    Agent.update(registry, fn tools -> Map.put(tools, name, tool_fn) end)
  end

  @doc """
  Gets a registered tool by name.

  ## Examples

      iex> {:ok, _pid} = AgentForge.Tools.start_link(name: :test_registry2)
      iex> AgentForge.Tools.register("uppercase", &String.upcase/1, :test_registry2)
      iex> {:ok, tool} = AgentForge.Tools.get("uppercase", :test_registry2)
      iex> tool.("hello")
      "HELLO"
      iex> AgentForge.Tools.get("nonexistent", :test_registry2)
      {:error, "Tool not found: nonexistent"}
  """
  def get(name, registry \\ __MODULE__) when is_binary(name) do
    case Agent.get(registry, fn tools -> Map.get(tools, name) end) do
      nil -> {:error, "Tool not found: #{name}"}
      tool_fn -> {:ok, tool_fn}
    end
  end

  @doc """
  Lists all registered tools.

  ## Examples

      iex> {:ok, _pid} = AgentForge.Tools.start_link(name: :test_registry3)
      iex> AgentForge.Tools.register("tool1", &String.upcase/1, :test_registry3)
      iex> AgentForge.Tools.register("tool2", &String.downcase/1, :test_registry3)
      iex> AgentForge.Tools.list(:test_registry3)
      ["tool1", "tool2"]
  """
  def list(registry \\ __MODULE__) do
    Agent.get(registry, fn tools -> Map.keys(tools) |> Enum.sort() end)
  end

  @doc """
  Creates a handler that executes a tool with the signal data.
  The result of the tool execution is emitted as a new signal.

  ## Examples

      iex> {:ok, _pid} = AgentForge.Tools.start_link(name: :test_registry4)
      iex> AgentForge.Tools.register("add_one", fn n -> n + 1 end, :test_registry4)
      iex> tool_handler = AgentForge.Tools.execute("add_one", :test_registry4)
      iex> signal = AgentForge.Signal.new(:number, 5)
      iex> {result, _} = tool_handler.(signal, %{})
      iex> match?({:emit, %{type: :tool_result, data: 6}}, result)
      true
  """
  def execute(tool_name, registry \\ __MODULE__) when is_binary(tool_name) do
    fn signal, state ->
      case get(tool_name, registry) do
        {:ok, tool_fn} ->
          try do
            result = tool_fn.(signal.data)

            meta =
              Map.merge(signal.meta, %{
                tool: tool_name,
                parent_trace_id: signal.meta.trace_id
              })

            {{:emit, Signal.new(:tool_result, result, meta)}, state}
          rescue
            e ->
              error = "Tool execution error: #{Exception.message(e)}"
              {{:emit, Signal.new(:error, error, %{tool: tool_name})}, state}
          end

        {:error, reason} ->
          {{:emit, Signal.new(:error, reason)}, state}
      end
    end
  end

  @doc """
  Creates a handler that executes multiple tools in sequence.
  Results are collected and emitted as multiple signals.

  ## Examples

      iex> {:ok, _pid} = AgentForge.Tools.start_link(name: :test_registry5)
      iex> AgentForge.Tools.register("uppercase", &String.upcase/1, :test_registry5)
      iex> AgentForge.Tools.register("reverse", &String.reverse/1, :test_registry5)
      iex> pipeline = AgentForge.Tools.execute_pipeline(["uppercase", "reverse"], :test_registry5)
      iex> signal = AgentForge.Signal.new(:text, "hello")
      iex> {result, _} = pipeline.(signal, %{})
      iex> match?({:emit_many, [_, _]}, result)
      true
  """
  def execute_pipeline(tool_names, registry \\ __MODULE__) when is_list(tool_names) do
    fn signal, state ->
      try do
        results =
          Enum.map(tool_names, fn name ->
            case get(name, registry) do
              {:ok, tool_fn} ->
                result = tool_fn.(signal.data)

                meta =
                  Map.merge(signal.meta, %{
                    tool: name,
                    parent_trace_id: signal.meta.trace_id
                  })

                Signal.new(:tool_result, result, meta)

              {:error, reason} ->
                raise reason
            end
          end)

        {{:emit_many, results}, state}
      rescue
        e ->
          error = "Tool pipeline error: #{Exception.message(e)}"
          {{:emit, Signal.new(:error, error)}, state}
      end
    end
  end
end
