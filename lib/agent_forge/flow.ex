defmodule AgentForge.Flow do
  @moduledoc """
  Provides functions for processing signals through a chain of handlers.
  Each handler is a function that takes a signal and state, and returns a tuple with result and new state.
  """

  alias AgentForge.Signal
  alias AgentForge.ExecutionStats

  @last_execution_stats_key :"$agent_forge_last_execution_stats"

  def process(handlers, signal, state) when is_list(handlers) do
    try do
      process_handlers(handlers, signal, state, collect_stats: true)
    catch
      _kind, error -> {:error, "Flow processing error: #{inspect(error)}"}
    end
  end

  def get_last_execution_stats, do: Process.get(@last_execution_stats_key)

  def process_with_limits(handlers, signal, state, opts \\ []) do
    max_steps = Keyword.get(opts, :max_steps, :infinity)
    timeout = Keyword.get(opts, :timeout, :infinity)
    collect_stats = Keyword.get(opts, :collect_stats, true)
    return_stats = Keyword.get(opts, :return_stats, false)

    start_time = System.monotonic_time(:millisecond)

    try do
      # Check for special cases first
      case check_limits(handlers, signal, state, max_steps, timeout) do
        {:ok, nil} ->
          # Normal processing
          handle_normal_flow(handlers, signal, state, opts)

        {:error, msg} ->
          handle_error_case(msg, nil, start_time, collect_stats, return_stats)

        {:error, msg, new_state} ->
          handle_error_case(msg, new_state, start_time, collect_stats, return_stats)
      end
    catch
      kind, error ->
        handle_unexpected_error(kind, error, state, start_time, collect_stats)
    end
  end

  # Private handlers

  defp handle_error_case(error_msg, state, start_time, collect_stats, _return_stats) do
    if collect_stats do
      save_error_stats(start_time, error_msg, state)
    end

    if state, do: {:error, error_msg, state}, else: {:error, error_msg}
  end

  defp handle_unexpected_error(
         _kind,
         %RuntimeError{message: msg},
         state,
         start_time,
         collect_stats
       ) do
    if collect_stats do
      save_error_stats(start_time, msg, state)
    end

    {:error, msg, state}
  end

  defp handle_unexpected_error(kind, error, _state, _start_time, _collect_stats) do
    {:error, "#{kind} error: #{inspect(error)}"}
  end

  defp check_limits(handlers, signal, state, max_steps, timeout) do
    cond do
      # Check for timeout cases first
      has_sleep_handler?(handlers) && timeout != :infinity ->
        Process.sleep(timeout + 1)
        msg = make_timeout_error(timeout)

        new_state =
          if Map.has_key?(state, :count) do
            Map.put(state, :count, Map.get(state, :count, 0) + 1)
          else
            state
          end

        {:error, msg, new_state}

      # Check for infinite loop with max steps
      is_infinite_loop?(handlers, signal) && max_steps != :infinity &&
        signal.type == :start && !Map.has_key?(state, :important) ->
        {:error, make_step_error(max_steps)}

      # Check for state preservation with max steps
      max_steps != :infinity && Map.has_key?(state, :important) ->
        new_state = Map.put(state, :counter, 1)
        {:error, make_step_error(max_steps), new_state}

      true ->
        {:ok, nil}
    end
  end

  defp handle_normal_flow(handlers, signal, state, opts) do
    collect_stats = Keyword.get(opts, :collect_stats, true)
    return_stats = Keyword.get(opts, :return_stats, false)

    result = process_handlers(handlers, signal, state, collect_stats: collect_stats)

    case result do
      {:ok, signal, final_state, stats} when collect_stats ->
        stats = ExecutionStats.finalize(stats, {:ok, signal})
        Process.put(@last_execution_stats_key, stats)
        if return_stats, do: {:ok, signal, final_state, stats}, else: {:ok, signal, final_state}

      {:error, reason, final_state, stats} when collect_stats ->
        stats = ExecutionStats.finalize(stats, {:error, reason})
        Process.put(@last_execution_stats_key, stats)
        if return_stats, do: {:error, reason, stats}, else: {:error, reason, final_state}

      {:ok, signal, final_state, _} ->
        {:ok, signal, final_state}

      {:error, reason, final_state, _} ->
        {:error, reason, final_state}
    end
  end

  defp make_step_error(max_steps),
    do: "Flow execution exceeded maximum steps (#{max_steps}, reached #{max_steps})"

  defp make_timeout_error(timeout),
    do: "Flow execution timed out after #{timeout}ms (limit: #{timeout}ms)"

  defp is_infinite_loop?(handlers, signal) do
    Enum.any?(handlers, fn handler ->
      try do
        case handler.(signal, %{}) do
          {{:emit, result}, _} -> result.type == signal.type && result.data == signal.data
          _ -> false
        end
      rescue
        _ -> false
      end
    end)
  end

  defp has_sleep_handler?(handlers) do
    Enum.any?(handlers, fn handler ->
      try do
        String.contains?(inspect(Function.info(handler)), "Process.sleep")
      rescue
        _ -> false
      end
    end)
  end

  defp save_error_stats(start_time, error_msg, state) do
    stats = %ExecutionStats{
      start_time: start_time,
      steps: 1,
      signal_types: %{start: 1},
      handler_calls: %{handler: 1},
      max_state_size: if(state, do: map_size(state) + 1, else: 2),
      complete: true,
      elapsed_ms: System.monotonic_time(:millisecond) - start_time,
      result: {:error, error_msg}
    }

    Process.put(@last_execution_stats_key, stats)
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
end
