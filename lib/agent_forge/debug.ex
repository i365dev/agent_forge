defmodule AgentForge.Debug do
  @moduledoc """
  Provides debug utilities for tracing and logging signals through the system.
  """

  require Logger

  @doc """
  Creates a debug handler that logs signal processing.
  Wraps an existing handler with debug logging.

  ## Examples

      iex> handler = fn signal, state -> {AgentForge.Signal.emit(:done, signal.data), state} end
      iex> debug_handler = AgentForge.Debug.trace_handler("test", handler)
      iex> signal = AgentForge.Signal.new(:test, "data")
      iex> {result, _state} = debug_handler.(signal, %{})
      iex> match?({:emit, %{type: :done}}, result)
      true
  """
  def trace_handler(name, handler) when is_binary(name) and is_function(handler, 2) do
    fn signal, state ->
      log_signal_processing(name, signal)
      result = handler.(signal, state)
      log_handler_result(name, result)
      result
    end
  end

  @doc """
  Logs a signal's journey through the system.
  """
  def log_signal_processing(context, signal) when is_binary(context) do
    Logger.debug(fn ->
      """
      [#{context}] Processing signal:
        Type: #{inspect(signal.type)}
        Data: #{inspect(signal.data)}
        Trace: #{inspect(signal.meta.trace_id)}
        Correlation: #{inspect(signal.meta.correlation_id)}
      """
    end)
  end

  @doc """
  Creates a debug flow that wraps each handler in debug logging.

  ## Examples

      iex> handlers = [
      ...>   fn signal, state -> {AgentForge.Signal.emit(:step1, signal.data), state} end,
      ...>   fn signal, state -> {AgentForge.Signal.emit(:step2, signal.data), state} end
      ...> ]
      iex> debug_flow = AgentForge.Debug.trace_flow("test_flow", handlers)
      iex> is_list(debug_flow) and length(debug_flow) == length(handlers)
      true
  """
  def trace_flow(name, handlers) when is_binary(name) and is_list(handlers) do
    handlers
    |> Enum.with_index()
    |> Enum.map(fn
      {handler, index} when is_function(handler, 2) ->
        trace_handler("#{name}[#{index}]", handler)

      {{handler, opts}, index} when is_function(handler, 2) ->
        {trace_handler("#{name}[#{index}]", handler), opts}
    end)
  end

  # Private Functions

  defp log_handler_result(name, {result, _state}) do
    Logger.debug(fn ->
      """
      [#{name}] Handler result:
        #{format_result(result)}
      """
    end)
  end

  defp format_result({:emit, signal}) do
    "Emit: #{inspect(signal.type)} -> #{inspect(signal.data)}"
  end

  defp format_result({:emit_many, signals}) do
    signals_info = Enum.map_join(signals, "\n    ", &"#{inspect(&1.type)} -> #{inspect(&1.data)}")
    "Emit Many:\n    #{signals_info}"
  end

  defp format_result({:halt, value}) do
    "Halt: #{inspect(value)}"
  end

  defp format_result(:skip) do
    "Skip"
  end
end
