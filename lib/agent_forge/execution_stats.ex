defmodule AgentForge.ExecutionStats do
  @moduledoc """
  Provides functionality for collecting and analyzing execution statistics of flows.
  Tracks metrics such as execution time, steps taken, and signal patterns.
  """

  @type t :: %__MODULE__{
          start_time: integer(),
          steps: non_neg_integer(),
          signal_types: %{atom() => non_neg_integer()},
          handler_calls: %{atom() => non_neg_integer()},
          max_state_size: non_neg_integer(),
          complete: boolean(),
          elapsed_ms: integer() | nil,
          result: any()
        }

  defstruct start_time: nil,
            steps: 0,
            signal_types: %{},
            handler_calls: %{},
            max_state_size: 0,
            complete: false,
            elapsed_ms: nil,
            result: nil

  @doc """
  Creates a new execution stats struct with initial values.

  ## Examples

      iex> stats = AgentForge.ExecutionStats.new()
      iex> is_integer(stats.start_time) and stats.steps == 0
      true
  """
  def new do
    %__MODULE__{
      start_time: System.monotonic_time(:millisecond)
    }
  end

  @doc """
  Records a step in the execution process, updating relevant statistics.

  ## Parameters

    * `stats` - Current execution stats struct
    * `handler_info` - Information about the handler being executed
    * `signal` - The signal being processed
    * `state` - Current state of the flow

  ## Examples

      iex> stats = AgentForge.ExecutionStats.new()
      iex> signal = %{type: :test, data: "data"}
      iex> updated = AgentForge.ExecutionStats.record_step(stats, :test_handler, signal, %{})
      iex> updated.steps == 1 and updated.signal_types == %{test: 1}
      true
  """
  def record_step(stats, handler_info, signal, state) do
    state_size = get_state_size(state)

    %{
      stats
      | steps: stats.steps + 1,
        signal_types: increment_counter(stats.signal_types, signal.type),
        handler_calls: increment_counter(stats.handler_calls, handler_info),
        max_state_size: max(stats.max_state_size, state_size)
    }
  end

  @doc """
  Finalizes the execution stats with the result and calculates elapsed time.

  ## Parameters

    * `stats` - Current execution stats struct
    * `result` - The final result of the flow execution

  ## Examples

      iex> stats = AgentForge.ExecutionStats.new()
      iex> final = AgentForge.ExecutionStats.finalize(stats, {:ok, "success"})
      iex> final.complete and is_integer(final.elapsed_ms) and final.result == {:ok, "success"}
      true
  """
  def finalize(stats, result) do
    %{
      stats
      | complete: true,
        elapsed_ms: System.monotonic_time(:millisecond) - stats.start_time,
        result: result
    }
  end

  @doc """
  Formats the execution stats into a human-readable report.

  ## Examples

      iex> stats = AgentForge.ExecutionStats.new()
      iex> stats = AgentForge.ExecutionStats.finalize(stats, {:ok, "success"})
      iex> report = AgentForge.ExecutionStats.format_report(stats)
      iex> String.contains?(report, "Total Steps: 0") and String.contains?(report, "Result: {:ok, \\"success\\"}")
      true
  """
  def format_report(stats) do
    """
    Execution Statistics:
    - Total Steps: #{stats.steps}
    - Elapsed Time: #{stats.elapsed_ms}ms
    - Signal Types: #{format_counters(stats.signal_types)}
    - Handler Calls: #{format_counters(stats.handler_calls)}
    - Max State Size: #{stats.max_state_size} entries
    - Result: #{inspect(stats.result)}
    """
  end

  # Private Functions

  defp increment_counter(counters, key) do
    Map.update(counters, key, 1, &(&1 + 1))
  end

  defp get_state_size(state) when is_map(state), do: map_size(state)
  defp get_state_size(_), do: 0

  defp format_counters(counters) do
    Enum.map_join(counters, ", ", fn {key, count} -> "#{key}: #{count}" end)
  end
end
