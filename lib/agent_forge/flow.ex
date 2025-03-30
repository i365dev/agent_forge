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

  @doc """
  Processes a signal through a list of handlers.
  For backward compatibility, does not return statistics by default.

  ## Examples

      iex> handlers = [
      ...>   fn sig, st -> {{:emit, AgentForge.Signal.new(:echo, sig.data)}, st} end
      ...> ]
      iex> signal = AgentForge.Signal.new(:test, "data")
      iex> {:ok, result, _} = AgentForge.Flow.process(handlers, signal, %{})
      iex> result.type
      :echo
  """
  def process(handlers, signal, state) when is_list(handlers) do
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
  rescue
    error -> {:error, "Flow processing error: #{inspect(error)}"}
  end

  @doc """
  Process a signal using a function flow.

  This allows defining a workflow as a function instead of a list of handlers.
  The function should accept a signal and state, and return one of:

  * `{:emit, new_signal, new_state}` - Emit a new signal and continue processing
  * `{:skip, new_state}` - Skip processing this signal
  * `{:halt, result, new_state}` - Halt processing with result
  * `{:error, reason, new_state}` - Halt with an error

  ## Options

  Same as `process_with_limits/4`.

  ## Example

  ```elixir
  function_flow = fn signal, state ->
    case signal.type do
      :start -> {:emit, Signal.new(:processing, signal.data), state}
      :processing -> {:halt, "Done processing", state}
      _ -> {:skip, state}
    end
  end

  Flow.process_function_flow(function_flow, signal, state)
  ```
  """
  def process_function_flow(flow_fn, signal, state, opts \\ []) when is_function(flow_fn, 2) do
    # Extract options
    timeout_ms = Keyword.get(opts, :timeout_ms, 30_000)
    collect_stats = Keyword.get(opts, :collect_stats, true)
    return_stats = Keyword.get(opts, :return_stats, false)

    # Initialize statistics if enabled
    stats = if collect_stats, do: ExecutionStats.new(), else: nil

    # Create a task to execute the function flow with timeout
    task =
      Task.async(fn ->
        try do
          # Execute the function flow
          result = flow_fn.(signal, state)
          # Normalize result format
          normalized_result = normalize_function_result(result, signal, state, stats)
          {normalized_result, stats}
        rescue
          e ->
            error_message = "Flow processing error: #{Exception.message(e)}"
            {{:error, error_message, state, stats}, stats}
        catch
          _kind, e ->
            error_message = "Flow processing error: #{inspect(e)}"
            {{:error, error_message, state, stats}, stats}
        end
      end)

    # Wait for the task to complete or timeout
    case Task.yield(task, timeout_ms) || Task.shutdown(task) do
      {:ok, {result, final_stats}} ->
        format_result(result, state, final_stats, return_stats)

      nil ->
        # Timeout occurred
        timeout_error = "Flow execution timed out after #{timeout_ms}ms"
        format_timeout_error(timeout_error, state, stats, return_stats)
    end
  end

  # Normalize result from function flow to match standard handler format
  defp normalize_function_result(result, _signal, state, stats) do
    case result do
      {:emit, new_signal, new_state} ->
        {:ok, new_signal, new_state, stats}

      {:skip, new_state} ->
        {:ok, nil, new_state, stats}

      {:halt, value, new_state} ->
        {:ok, value, new_state, stats}

      {:error, reason, new_state} ->
        {:error, reason, new_state, stats}

      # Handle legacy result format
      {signal_result, new_state} ->
        case signal_result do
          {:emit, new_signal} -> {:ok, new_signal, new_state, stats}
          :skip -> {:ok, nil, new_state, stats}
          {:halt, result} -> {:ok, result, new_state, stats}
          {:error, reason} -> {:error, reason, new_state, stats}
          _ -> {:error, "Invalid result format: #{inspect(signal_result)}", state, stats}
        end

      # State-only result (treat as a successful flow with no output signal)
      %{} = new_state ->
        {:ok, nil, new_state, stats}

      # Unrecognized format
      other ->
        {:error, "Unrecognized flow result: #{inspect(other)}", state, stats}
    end
  end

  @doc """
  Processes a signal through a list of handlers with execution limits.
  Supports timeout to prevent long-running processes.

  ## Options

  * `:timeout_ms` - Maximum time in milliseconds to process (default: 30000)
  * `:collect_stats` - Whether to collect execution statistics (default: true)
  * `:return_stats` - Whether to return statistics in the result (default: false)
  * `:continue_on_skip` - Whether to continue processing after a skip result (default: false)
  * `:signal_strategy` - How to handle emitted signals: `:forward` (default), `:restart`, or `:transform`
  * `:transform_fn` - Function to transform signals when signal_strategy is `:transform`

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
    timeout_ms = Keyword.get(opts, :timeout_ms, 30_000)
    collect_stats = Keyword.get(opts, :collect_stats, true)
    return_stats = Keyword.get(opts, :return_stats, false)

    # Initialize statistics if enabled
    stats = if collect_stats, do: ExecutionStats.new(), else: nil

    # Create a task to process the signal with timeout
    task = Task.async(fn -> execute_flow_safely(handlers, signal, state, stats, opts) end)

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
  defp process_with_stats(handlers, signal, state, nil, opts) do
    # No stats collection, use direct processing
    {process_handlers(handlers, signal, state, Keyword.put(opts, :collect_stats, false)), nil}
  end

  defp process_with_stats(handlers, signal, state, stats, opts) do
    # Pass options to process_handlers
    result = process_handlers(handlers, signal, state, Keyword.put(opts, :collect_stats, true))

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

  @doc """
  Process a single handler with a signal and state.
  This is the core function that executes a single handler.

  ## Examples

      iex> handler = fn sig, st -> {{:emit, AgentForge.Signal.new(:echo, sig.data)}, st} end
      iex> signal = AgentForge.Signal.new(:test, "data")
      iex> result = AgentForge.Flow.process_handler(handler, signal, %{})
      iex> match?({_, _}, result)
      true
  """
  def process_handler(handler, signal, state) when is_function(handler, 2) do
    handler.(signal, state)
  end

  # Process handlers with options for flow control.
  #
  # Handler Result Types:
  #
  # - `{{:emit, new_signal}, new_state}` - Handler emits a new signal to be processed
  # - `{:skip, new_state}` - Handler skips processing this signal
  # - `{{:error, reason}, new_state}` - Handler encounters an error
  # - `{:branch, condition, true_state, false_state}` - Handler branches based on condition
  #
  # Options:
  #
  # * `:collect_stats` - Whether to collect execution statistics
  # * `:continue_on_skip` - Whether to continue processing after a skip result
  # * `:signal_strategy` - How to handle emitted signals: `:forward`, `:restart`, or `:transform`
  # * `:transform_fn` - Function to transform signals when signal_strategy is `:transform`
  defp process_handlers(handlers, signal, state, opts) do
    collect_stats = Keyword.get(opts, :collect_stats, true)
    continue_on_skip = Keyword.get(opts, :continue_on_skip, false)
    signal_strategy = Keyword.get(opts, :signal_strategy, :forward)
    transform_fn = Keyword.get(opts, :transform_fn, & &1)

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
        # Enhanced emit handling with signal strategies
        {{:emit, new_signal}, new_state} ->
          case signal_strategy do
            :forward ->
              # Default behavior: forward signal to next handler
              {:cont, {:ok, new_signal, new_state, updated_stats}}

            :restart ->
              # Restart processing chain with new signal
              result = process_handlers(handlers, new_signal, new_state, opts)
              {:halt, result}

            :transform ->
              # Transform signal using provided function
              transformed_signal = transform_fn.(new_signal)
              {:cont, {:ok, transformed_signal, new_state, updated_stats}}
          end

        # Support for emit_many format
        {{:emit_many, signals}, new_state} when is_list(signals) ->
          # When multiple signals are emitted, use the last one for continuation
          last_signal = List.last(signals)
          {:cont, {:ok, last_signal, new_state, updated_stats}}

        # Enhanced skip handling with continue_on_skip option
        {:skip, new_state} ->
          if continue_on_skip do
            # Continue to next handler with current signal
            {:cont, {:ok, current_signal, new_state, updated_stats}}
          else
            # Original behavior: halt processing
            {:halt, {:ok, nil, new_state, updated_stats}}
          end

        # Error handling (unchanged)
        {{:error, reason}, new_state} ->
          {:halt, {:error, reason, new_state, updated_stats}}

        # Support for alternative halt format
        {:halt, result} ->
          {:halt, {:ok, result, current_state, updated_stats}}

        # Support for halt with state
        {{:halt, result}, new_state} ->
          {:halt, {:ok, result, new_state, updated_stats}}

        # New branch control flow
        {:branch, condition, true_state, false_state} ->
          if condition do
            # Take the true branch
            {:cont, {:ok, current_signal, true_state, updated_stats}}
          else
            # Take the false branch
            {:cont, {:ok, current_signal, false_state, updated_stats}}
          end

        # Invalid result handling
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

  # Safely executes a flow with exception handling
  defp execute_flow_safely(handlers, signal, state, stats, opts) do
    process_with_stats(handlers, signal, state, stats, opts)
  rescue
    error ->
      error_message = "Flow processing error: #{inspect(error)}"
      error_result = {:error, error_message, state, stats}
      {error_result, stats}
  catch
    _kind, error ->
      error_message = "Flow processing error: #{inspect(error)}"
      error_result = {:error, error_message, state, stats}
      {error_result, stats}
  end

  def get_last_execution_stats, do: Process.get(@last_execution_stats_key)
end
