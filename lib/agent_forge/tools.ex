defmodule AgentForge.Tools do
  @moduledoc """
  Manages a registry of tools that can be used in workflows.
  Each tool is a function that can be executed with input data and returns a result.
  """

  use GenServer
  alias AgentForge.Signal

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Registers a tool function with a given name.
  """
  def register(name, function, registry \\ __MODULE__) when is_binary(name) and is_function(function, 1) do
    GenServer.call(registry, {:register, name, function})
  end

  @doc """
  Unregisters a tool by name.
  """
  def unregister(name, registry \\ __MODULE__) when is_binary(name) do
    GenServer.call(registry, {:unregister, name})
  end

  @doc """
  Retrieves a tool by name.
  """
  def get(name, registry \\ __MODULE__) when is_binary(name) do
    GenServer.call(registry, {:get, name})
  end

  @doc """
  Lists all registered tools.
  """
  def list(registry \\ __MODULE__) do
    GenServer.call(registry, :list)
  end

  @doc """
  Creates a function that executes a registered tool.
  """
  def execute(name, registry \\ __MODULE__) when is_binary(name) do
    fn signal, state ->
      case get(name, registry) do
        {:ok, tool_fn} ->
          try do
            result = tool_fn.(signal.data)
            meta = Map.merge(signal.meta, %{
              tool: name,
              parent_trace_id: signal.meta.trace_id,
              last_tool: name
            })
            {{:emit, Signal.new(:tool_result, result, meta)}, state}
          rescue
            e ->
              meta = Map.merge(signal.meta, %{tool: name})
              {{:emit, Signal.new(:error, "Tool error: #{Exception.message(e)}", meta)}, state}
          end
        {:error, reason} ->
          meta = Map.merge(signal.meta, %{tool: name})
          {{:emit, Signal.new(:error, reason, meta)}, state}
      end
    end
  end

  @doc """
  Creates a function that executes multiple tools in sequence.
  """
  def execute_pipeline(tool_names, registry \\ __MODULE__) when is_list(tool_names) do
    fn signal, state ->
      results = Enum.reduce_while(tool_names, [], fn name, acc ->
        case get(name, registry) do
          {:ok, tool_fn} ->
            try do
              result = tool_fn.(signal.data)
              meta = Map.merge(signal.meta, %{
                tool: name,
                last_tool: name,
                parent_trace_id: signal.meta.trace_id
              })
              new_signal = Signal.new(:tool_result, result, meta)
              {:cont, [new_signal | acc]}
            rescue
              e ->
                meta = Map.merge(signal.meta, %{tool: name})
                signal = Signal.new(:error, "Tool error: #{Exception.message(e)}", meta)
                {:halt, {:error, signal}}
            end
          {:error, reason} ->
            meta = Map.merge(signal.meta, %{tool: name})
            signal = Signal.new(:error, reason, meta)
            {:halt, {:error, signal}}
        end
      end)

      case results do
        {:error, error_signal} ->
          {{:emit, error_signal}, state}
        signals when is_list(signals) ->
          {{:emit_many, Enum.reverse(signals)}, state}
      end
    end
  end

  # Server callbacks

  @impl true
  def init(tools) do
    {:ok, tools}
  end

  @impl true
  def handle_call({:register, name, function}, _from, tools) do
    {:reply, :ok, Map.put(tools, name, function)}
  end

  @impl true
  def handle_call({:unregister, name}, _from, tools) do
    {:reply, :ok, Map.delete(tools, name)}
  end

  @impl true
  def handle_call({:get, name}, _from, tools) do
    case Map.fetch(tools, name) do
      {:ok, function} -> {:reply, {:ok, function}, tools}
      :error -> {:reply, {:error, "Tool not found: #{name}"}, tools}
    end
  end

  @impl true
  def handle_call(:list, _from, tools) do
    tool_list = tools |> Map.keys() |> Enum.sort()
    {:reply, tool_list, tools}
  end
end
