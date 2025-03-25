defmodule AgentForge.Flow do
  @moduledoc """
  Provides functions for processing signals through a chain of handlers.
  Each handler is a function that takes a signal and state, and returns a tuple with result and new state.
  Automatically collects execution statistics for monitoring and debugging.
  """

  alias AgentForge.Signal
  alias AgentForge.ExecutionStats

  # Store last execution stats in module attribute
  @last_execution_stats_key :"$agent_forge_last_execution_stats"

  @doc """
  Processes a signal through a list of handlers.
  Each handler should return a tuple {{:emit, signal} | {:error, reason}, new_state}.
  """
  def process(handlers, signal, state) when is_list(handlers) do
    try do
      process_handlers(handlers, signal, state)
      |> handle_result()
    catch
      _kind, error ->
        {:error, "Flow processing error: #{inspect(error)}"}
    end
  end

  @doc """
  Creates a handler that always emits the same signal type and data.
  """
  def always_emit(type, data) do
    fn _signal, state ->
      {{:emit, Signal.new(type, data)}, state}
    end
  end

  @doc """
  Creates a handler that filters signals by type.
  """
  def filter_type(expected_type, inner_handler) do
    fn signal, state ->
      if signal.type == expected_type do
        inner_handler.(signal, state)
      else
        {:skip, state}
      end
    end
  end

  @doc """
  Creates a handler that stores signal data in state under a key.
  """
  def store_in_state(key) do
    fn signal, state ->
      {:skip, Map.put(state, key, signal.data)}
    end
  end

  @doc """
  Processes a single handler function with a signal and state.
  """
  def process_handler(handler, signal, state) when is_function(handler, 2) do
    handler.(signal, state)
  end

  # Private functions

  defp process_handlers(handlers, signal, state) do
    stats = ExecutionStats.new()

    Enum.reduce_while(handlers, {:ok, signal, state, stats}, fn handler,
                                                                {:ok, current_signal,
                                                                 current_state, current_stats} ->
      # Record step before processing
      updated_stats =
        ExecutionStats.record_step(current_stats, handler, current_signal, current_state)

      case process_handler(handler, current_signal, current_state) do
        {{:emit, new_signal}, new_state} ->
          {:cont, {:ok, new_signal, new_state, updated_stats}}

        {{:emit_many, signals}, new_state} when is_list(signals) ->
          # When multiple signals are emitted, use the last one for continuation
          {:cont, {:ok, List.last(signals), new_state, updated_stats}}

        {:skip, new_state} ->
          {:halt, {:ok, nil, new_state, updated_stats}}

        {:halt, data} ->
          {:halt, {:ok, data, state, updated_stats}}

        {{:halt, data}, _state} ->
          {:halt, {:ok, data, state, updated_stats}}

        {{:error, reason}, new_state} ->
          {:halt, {:error, reason, new_state, updated_stats}}

        {other, _} ->
          raise "Invalid handler result: #{inspect(other)}"

        other ->
          raise "Invalid handler result: #{inspect(other)}"
      end
    end)
  end

  # Handle the final result
  defp handle_result({:ok, signal, state, stats}) do
    final_stats = ExecutionStats.finalize(stats, {:ok, signal})
    Process.put(@last_execution_stats_key, final_stats)
    {:ok, signal, state}
  end

  defp handle_result({:error, reason, _state, stats}) do
    final_stats = ExecutionStats.finalize(stats, {:error, reason})
    Process.put(@last_execution_stats_key, final_stats)
    {:error, reason}
  end

  @doc """
  Returns statistics from the last flow execution.
  Returns nil if no flow has been executed yet.
  """
  def get_last_execution_stats do
    Process.get(@last_execution_stats_key)
  end
end
