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
      |> handle_base_result()
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

  @doc """
  Returns statistics from the last flow execution.
  Returns nil if no flow has been executed yet.
  """
  def get_last_execution_stats do
    Process.get(@last_execution_stats_key)
  end

  @doc """
  Processes a signal through a list of handlers with execution limits.
  """
  def process_with_limits(handlers, signal, state, opts \\ []) do
    # Extract options
    max_steps = Keyword.get(opts, :max_steps, :infinity)
    timeout = Keyword.get(opts, :timeout, :infinity)
    collect_stats = Keyword.get(opts, :collect_stats, true)
    return_stats = Keyword.get(opts, :return_stats, false)

    # Initialize stats
    stats = if collect_stats, do: ExecutionStats.new(), else: nil

    # Track execution context
    context = %{
      step_count: 0,
      start_time: System.monotonic_time(:millisecond),
      max_steps: max_steps,
      timeout: timeout,
      stats: stats
    }

    try do
      # Check initial limits
      case check_limits!(context) do
        :ok ->
          run_with_limits(handlers, signal, state, context)
          |> handle_result(return_stats)

        {:error, reason} ->
          handle_error(reason, state, stats, return_stats)
      end
    catch
      :throw, {:limit_error, msg} ->
        handle_error(msg, state, stats, return_stats)

      kind, error ->
        msg = "Flow processing error: #{inspect(kind)} - #{inspect(error)}"
        handle_error(msg, state, stats, return_stats)
    end
  end

  # Private functions

  defp run_with_limits(handlers, signal, state, context) do
    Enum.reduce_while(handlers, {:ok, signal, state, context}, fn handler,
                                                                  {:ok, current_signal,
                                                                   current_state,
                                                                   current_context} ->
      next_context = %{current_context | step_count: current_context.step_count + 1}

      case check_limits!(next_context) do
        :ok ->
          # Record step in stats if enabled
          next_context =
            if next_context.stats do
              %{
                next_context
                | stats:
                    ExecutionStats.record_step(
                      next_context.stats,
                      handler,
                      current_signal,
                      current_state
                    )
              }
            else
              next_context
            end

          # Process handler
          case process_handler(handler, current_signal, current_state) do
            {{:emit, new_signal}, new_state} ->
              {:cont, {:ok, new_signal, new_state, next_context}}

            {{:emit_many, signals}, new_state} when is_list(signals) ->
              {:cont, {:ok, List.last(signals), new_state, next_context}}

            {:skip, new_state} ->
              {:halt, {:ok, nil, new_state, next_context}}

            {:halt, data} ->
              {:halt, {:ok, data, current_state, next_context}}

            {{:halt, data}, _state} ->
              {:halt, {:ok, data, current_state, next_context}}

            {{:error, reason}, new_state} ->
              {:halt, {:error, reason, new_state, next_context}}

            {other, _} ->
              raise "Invalid handler result: #{inspect(other)}"

            other ->
              raise "Invalid handler result: #{inspect(other)}"
          end

        {:error, reason} ->
          {:halt, {:error, reason, current_state, next_context}}
      end
    end)
  end

  defp check_limits!(context) do
    # Check max steps
    if context.max_steps != :infinity and context.step_count > context.max_steps do
      throw({:limit_error, "Flow execution exceeded maximum steps (#{context.max_steps})"})
    end

    # Check timeout
    if context.timeout != :infinity do
      elapsed = System.monotonic_time(:millisecond) - context.start_time

      if elapsed >= context.timeout do
        throw(
          {:limit_error,
           "Flow execution timed out after #{elapsed}ms (limit: #{context.timeout}ms)"}
        )
      end
    end

    :ok
  end

  defp handle_result({:ok, signal, state, context}, return_stats) do
    if context.stats do
      final_stats = ExecutionStats.finalize(context.stats, {:ok, signal})

      if return_stats do
        {:ok, signal, state, final_stats}
      else
        Process.put(@last_execution_stats_key, final_stats)
        {:ok, signal, state}
      end
    else
      {:ok, signal, state}
    end
  end

  defp handle_result({:error, reason, state, context}, return_stats) do
    if context.stats do
      final_stats = ExecutionStats.finalize(context.stats, {:error, reason})

      if return_stats do
        {:error, reason, state, final_stats}
      else
        Process.put(@last_execution_stats_key, final_stats)
        {:error, reason, state}
      end
    else
      {:error, reason, state}
    end
  end

  defp handle_error(reason, state, stats, return_stats) do
    if stats do
      final_stats = ExecutionStats.finalize(stats, {:error, reason})

      if return_stats do
        {:error, reason, state, final_stats}
      else
        Process.put(@last_execution_stats_key, final_stats)
        {:error, reason, state}
      end
    else
      {:error, reason, state}
    end
  end

  defp process_handlers(handlers, signal, state) do
    stats = ExecutionStats.new()

    Enum.reduce_while(handlers, {:ok, signal, state, stats}, fn handler,
                                                                {:ok, current_signal,
                                                                 current_state, current_stats} ->
      updated_stats =
        ExecutionStats.record_step(current_stats, handler, current_signal, current_state)

      case process_handler(handler, current_signal, current_state) do
        {{:emit, new_signal}, new_state} ->
          {:cont, {:ok, new_signal, new_state, updated_stats}}

        {{:emit_many, signals}, new_state} when is_list(signals) ->
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

  defp handle_base_result({:ok, signal, state, stats}) do
    final_stats = ExecutionStats.finalize(stats, {:ok, signal})
    Process.put(@last_execution_stats_key, final_stats)
    {:ok, signal, state}
  end

  defp handle_base_result({:error, reason, _state, stats}) do
    final_stats = ExecutionStats.finalize(stats, {:error, reason})
    Process.put(@last_execution_stats_key, final_stats)
    {:error, reason}
  end
end
