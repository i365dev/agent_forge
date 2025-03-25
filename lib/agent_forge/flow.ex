defmodule AgentForge.Flow do
  @moduledoc """
  Provides functions for processing signals through a chain of handlers.
  Each handler is a function that takes a signal and state, and returns a tuple with result and new state.
  """

  alias AgentForge.ExecutionStats
  alias AgentForge.Signal

  @last_execution_stats_key :"$agent_forge_last_execution_stats"

  @typedoc """
  A flow is a handler function or a list of handler functions.
  Each handler takes a signal and state, and returns a tuple with result and new state.
  """
  @type flow :: (Signal.t(), map() -> {term(), map()}) | [(Signal.t(), map() -> {term(), map()})]

  def process(handlers, signal, state) when is_list(handlers) do
    try do
      # Call process_with_limits with default option to not return statistics
      # This ensures backward compatibility with existing code
      case process_with_limits(handlers, signal, state, return_stats: false) do
        {:ok, result, new_state} ->
          {:ok, result, new_state}

        {:error, reason, _state} ->
          # Maintain original error format for backward compatibility
          {:error, reason}

        other ->
          other
      end
    catch
      _kind, error -> {:error, "Flow processing error: #{inspect(error)}"}
    end
  end

  def get_last_execution_stats, do: Process.get(@last_execution_stats_key)

  @doc """
  Processes a signal through a list of handlers with execution limits.
  Supports timeout to prevent long-running processes.

  ## Options

  * `:timeout_ms` - Maximum time in milliseconds to process (default: 30000)
  * `:collect_stats` - Whether to collect execution statistics (default: true)
  * `:return_stats` - Whether to return statistics in the result (default: false)

  ## Examples

      iex> handlers = [
      ...>   fn sig, st -> {{:emit, AgentForge.Signal.new(:echo, sig.data)}, st} end
      ...> ]
      iex> signal = AgentForge.Signal.new(:test, "data")
      iex> {:ok, result, _} = AgentForge.Flow.process_with_limits(handlers, signal, %{})
      iex> result.type
      :echo
      
  With statistics:

      iex> handlers = [
      ...>   fn sig, st -> {{:emit, AgentForge.Signal.new(:echo, sig.data)}, st} end
      ...> ]
      iex> signal = AgentForge.Signal.new(:test, "data")
      iex> {:ok, _result, _, stats} = AgentForge.Flow.process_with_limits(handlers, signal, %{}, return_stats: true)
      iex> stats.steps >= 1
      true
  """
  def process_with_limits(handlers, signal, state, opts \\ []) when is_list(handlers) do
    # Extract options
    timeout_ms = Keyword.get(opts, :timeout_ms, 30000)
    collect_stats = Keyword.get(opts, :collect_stats, true)
    return_stats = Keyword.get(opts, :return_stats, false)

    # Initialize statistics if enabled
    stats = if collect_stats, do: ExecutionStats.new(), else: nil

    # Create a task to process the signal with timeout
    # Use try-catch to wrap processing logic to ensure exceptions are properly caught
    task =
      Task.async(fn ->
        try do
          process_with_stats(handlers, signal, state, stats)
        catch
          # Explicitly catch exceptions and convert them to appropriate error results
          _kind, error ->
            error_message = "Flow processing error: #{inspect(error)}"
            error_result = {:error, error_message, state, stats}
            {error_result, stats}
        end
      end)

    # Wait for the task to complete or timeout
    case Task.yield(task, timeout_ms) || Task.shutdown(task) do
      {:ok, {result, final_stats}} ->
        format_result(result, state, final_stats, return_stats)

      nil ->
        # Timeout occurred - create error result
        timeout_error = "Flow execution timed out after #{timeout_ms}ms"
        format_timeout_error(timeout_error, state, stats, return_stats)
    end
  end

  # Process with statistics collection
  defp process_with_stats(handlers, signal, state, nil) do
    # No stats collection, use direct processing
    {process_handlers(handlers, signal, state, collect_stats: false), nil}
  end

  defp process_with_stats(handlers, signal, state, stats) do
    # Process with statistics collection
    result =
      Enum.reduce_while(handlers, {:ok, signal, state, stats}, fn handler,
                                                                  {:ok, current_signal,
                                                                   current_state,
                                                                   current_stats} ->
        # Record step statistics
        updated_stats =
          ExecutionStats.record_step(current_stats, handler, current_signal, current_state)

        # Process handler
        case process_handler(handler, current_signal, current_state) do
          {{:emit, new_signal}, new_state} ->
            {:cont, {:ok, new_signal, new_state, updated_stats}}

          {{:emit_many, signals}, new_state} when is_list(signals) ->
            # When multiple signals are emitted, use the last one for continuation
            {:cont, {:ok, List.last(signals), new_state, updated_stats}}

          {:skip, new_state} ->
            {:halt, {:ok, nil, new_state, updated_stats}}

          {:halt, data} ->
            {:halt, {:ok, data, current_state, updated_stats}}

          {{:halt, data}, _state} ->
            {:halt, {:ok, data, current_state, updated_stats}}

          {{:error, reason}, new_state} ->
            {:halt, {:error, reason, new_state, updated_stats}}

          {other, _} ->
            raise "Invalid handler result: #{inspect(other)}"

          other ->
            raise "Invalid handler result: #{inspect(other)}"
        end
      end)

    # Extract stats from result
    {result,
     case result do
       {:ok, _, _, stats} -> stats
       {:error, _, _, stats} -> stats
       # Fallback for unexpected result format
       _ -> stats
     end}
  end

  # Format successful result
  defp format_result({:ok, result, state, _stats}, _orig_state, nil, _return_stats) do
    {:ok, result, state}
  end

  defp format_result({:ok, result, state, _stats}, _orig_state, final_stats, true) do
    # Return stats when requested
    stats = ExecutionStats.finalize(final_stats, {:ok, result})
    {:ok, result, state, stats}
  end

  defp format_result({:ok, result, state, _stats}, _orig_state, final_stats, false) do
    # Save stats to process dictionary
    stats = ExecutionStats.finalize(final_stats, {:ok, result})
    Process.put(@last_execution_stats_key, stats)
    {:ok, result, state}
  end

  # Format error result
  defp format_result({:error, reason, state, _stats}, _orig_state, nil, _return_stats) do
    {:error, reason, state}
  end

  defp format_result({:error, reason, state, _stats}, _orig_state, final_stats, true) do
    # Return stats when requested
    stats = ExecutionStats.finalize(final_stats, {:error, reason})
    {:error, reason, state, stats}
  end

  defp format_result({:error, reason, state, _stats}, _orig_state, final_stats, false) do
    # Save stats to process dictionary
    stats = ExecutionStats.finalize(final_stats, {:error, reason})
    Process.put(@last_execution_stats_key, stats)
    {:error, reason, state}
  end

  # Handle timeout error
  defp format_timeout_error(error_msg, state, nil, _return_stats) do
    {:error, error_msg, state}
  end

  defp format_timeout_error(error_msg, state, stats, true) do
    # Return stats when requested
    final_stats = ExecutionStats.finalize(stats, {:error, error_msg})
    {:error, error_msg, state, final_stats}
  end

  defp format_timeout_error(error_msg, state, stats, false) do
    # Save stats to process dictionary
    final_stats = ExecutionStats.finalize(stats, {:error, error_msg})
    Process.put(@last_execution_stats_key, final_stats)
    {:error, error_msg, state}
  end

  def process_handler(handler, signal, state) when is_function(handler, 2) do
    handler.(signal, state)
  end

  defp process_handlers(handlers, signal, state, opts) do
    collect_stats = Keyword.get(opts, :collect_stats, true)
    stats = if collect_stats, do: ExecutionStats.new(), else: nil

    Enum.reduce_while(handlers, {:ok, signal, state, stats}, fn handler,
                                                                {:ok, current_signal,
                                                                 current_state, current_stats} ->
      # Update stats if enabled
      updated_stats =
        if current_stats,
          do: ExecutionStats.record_step(current_stats, handler, current_signal, current_state),
          else: nil

      # Process handler
      case process_handler(handler, current_signal, current_state) do
        {{:emit, new_signal}, new_state} ->
          {:cont, {:ok, new_signal, new_state, updated_stats}}

        {:skip, new_state} ->
          {:halt, {:ok, nil, new_state, updated_stats}}

        {{:error, reason}, new_state} ->
          {:halt, {:error, reason, new_state, updated_stats}}

        other ->
          raise "Invalid handler result: #{inspect(other)}"
      end
    end)
  end

  @doc """
  Creates a handler that always emits a signal of the given type and data.

  ## Examples

      iex> handler = AgentForge.Flow.always_emit(:done, "success")
      iex> {result, state} = handler.(nil, %{})
      iex> match?({:emit, %{type: :done, data: "success"}}, result)
      true
  """
  def always_emit(type, data) do
    fn _signal, state ->
      {Signal.emit(type, data), state}
    end
  end

  @doc """
  Creates a handler that only processes signals of a specific type.
  Other signal types are skipped.

  ## Examples

      iex> inner = fn signal, state -> {AgentForge.Signal.emit(:processed, signal.data), state} end
      iex> handler = AgentForge.Flow.filter_type(:test, inner)
      iex> test_signal = AgentForge.Signal.new(:test, "data")
      iex> {result, _} = handler.(test_signal, %{})
      iex> match?({:emit, %{type: :processed}}, result)
      true
      iex> other_signal = AgentForge.Signal.new(:other, "data")
      iex> handler.(other_signal, %{}) |> elem(0)
      :skip
  """
  def filter_type(type, handler) do
    fn signal, state ->
      if signal.type == type do
        handler.(signal, state)
      else
        {:skip, state}
      end
    end
  end

  @doc """
  Creates a handler that stores the signal data in state under the given key.

  ## Examples

      iex> handler = AgentForge.Flow.store_in_state(:last_message)
      iex> signal = AgentForge.Signal.new(:test, "data")
      iex> {result, state} = handler.(signal, %{})
      iex> result
      :skip
      iex> state.last_message
      "data"
  """
  def store_in_state(key) do
    fn signal, state ->
      {:skip, Map.put(state, key, signal.data)}
    end
  end
end
