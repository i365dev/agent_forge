defmodule AgentForge.Flow do
  @moduledoc """
  Handles the composition and execution of signal handlers in a processing pipeline.
  Flows are sequences of handlers that process signals and maintain state.
  """

  alias AgentForge.Signal

  @type handler :: (Signal.t(), term() -> {Signal.signal_result(), term()})
  @type handler_with_opts :: {handler(), keyword()}
  @type flow :: [handler() | handler_with_opts()]

  @doc """
  Processes a signal through a flow of handlers.
  Returns the final result and state after processing through all handlers.

  ## Examples

      iex> handler = fn signal, state ->
      ...>   {{:emit, AgentForge.Signal.new(:processed, signal.data)}, state}
      ...> end
      iex> signal = AgentForge.Signal.new(:test, "data")
      iex> {:ok, result, _state} = AgentForge.Flow.process([handler], signal, %{})
      iex> result.type == :processed
      true
  """
  @spec process(flow(), Signal.t(), term()) :: {:ok, Signal.t() | term(), term()} | {:error, term()}
  def process(handlers, signal, initial_state) when is_list(handlers) do
    try do
      process_handlers(handlers, signal, initial_state)
    rescue
      e ->
        {:error, "Flow processing error: #{inspect(e)}"}
    end
  end

  @doc """
  Creates a new handler that always emits a specific signal type.

  ## Examples

      iex> handler = AgentForge.Flow.always_emit(:done, "completed")
      iex> {result, _state} = handler.(nil, %{})
      iex> match?({:emit, %{type: :done, data: "completed"}}, result)
      true
  """
  def always_emit(type, data, meta \\ %{}) do
    fn _signal, state -> {Signal.emit(type, data, meta), state} end
  end

  @doc """
  Creates a new handler that filters signals based on type.
  Only processes signals of the specified type, skips others.

  ## Examples

      iex> handler = AgentForge.Flow.filter_type(:test, fn signal, state ->
      ...>   {AgentForge.Signal.emit(:processed, signal.data), state}
      ...> end)
      iex> signal = AgentForge.Signal.new(:test, "data")
      iex> {result, _state} = handler.(signal, %{})
      iex> match?({:emit, %{type: :processed}}, result)
      true
  """
  def filter_type(type, handler) when is_atom(type) and is_function(handler, 2) do
    fn signal, state ->
      if signal.type == type do
        handler.(signal, state)
      else
        {:skip, state}
      end
    end
  end

  @doc """
  Creates a new handler that updates state with signal data.

  ## Examples

      iex> handler = AgentForge.Flow.store_in_state(:last_message)
      iex> signal = AgentForge.Signal.new(:message, "Hello")
      iex> {_result, state} = handler.(signal, %{})
      iex> state.last_message == "Hello"
      true
  """
  def store_in_state(key) when is_atom(key) do
    fn signal, state ->
      {:skip, Map.put(state, key, signal.data)}
    end
  end

  # Private Functions

  defp process_handlers(handlers, signal, initial_state) do
    Enum.reduce_while(handlers, {signal, initial_state}, fn
      handler, {current_signal, current_state} when is_function(handler, 2) ->
        handle_result(handler.(current_signal, current_state))

      {handler, _opts}, {current_signal, current_state} when is_function(handler, 2) ->
        handle_result(handler.(current_signal, current_state))
    end)
    |> case do
      {:halt, result, final_state} -> {:ok, result, final_state}
      {signal, final_state} -> {:ok, signal, final_state}
    end
  end

  defp handle_result({{:emit, signal}, new_state}) do
    {:cont, {signal, new_state}}
  end

  defp handle_result({{:emit_many, [signal | _] = _signals}, new_state}) do
    # For now, we just take the first signal. In the future, we could process all signals
    {:cont, {signal, new_state}}
  end

  defp handle_result({{:halt, result}, new_state}) do
    {:halt, {:halt, result, new_state}}
  end

  defp handle_result({:skip, new_state}) do
    {:halt, {:halt, nil, new_state}}
  end
end
