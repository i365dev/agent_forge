defmodule AgentForge do
  @moduledoc ~S"""
  AgentForge is a lightweight, signal-driven workflow framework designed for personal projects.

  ## Key Features

  - Signal-based communication
  - Composable handler pipelines
  - Persistent state management
  - Debug tracing support

  ## Example

      # Define a simple handler
      message_handler = fn signal, state ->
        new_state = Map.put(state, :last_message, signal.data)
        {AgentForge.Signal.emit(:processed, "Got: #{signal.data}"), new_state}
      end

      # Create a flow with the handler
      flow = AgentForge.new_flow([message_handler], debug: true)

      # Execute the flow with a signal
      {:ok, result, _state} = flow.(AgentForge.Signal.new(:message, "Hello"))
      # result.data will be "Got: Hello"
  """

  alias AgentForge.{Signal, Runtime}

  @doc """
  Creates a new flow with the given handlers and options.
  Returns a function that can be used to execute the flow.

  ## Options

  All options from `AgentForge.Runtime.execute/3` are supported.

  ## Examples

      iex> handler = fn signal, state ->
      ...>   {AgentForge.Signal.emit(:echo, signal.data), state}
      ...> end
      iex> flow = AgentForge.new_flow([handler])
      iex> {:ok, result, _} = flow.(AgentForge.Signal.new(:test, "hello"))
      iex> result.data
      "hello"
  """
  def new_flow(handlers, opts \\ []) do
    Runtime.configure(handlers, opts)
  end

  @doc """
  Creates a new stateful flow that maintains state between executions.
  Similar to new_flow/2 but automatically stores and retrieves state.

  ## Examples

      iex> {:ok, _pid} = AgentForge.Store.start_link(name: :test_store)
      iex> counter = fn _signal, state ->
      ...>   count = Map.get(state, :count, 0) + 1
      ...>   {AgentForge.Signal.emit(:count, count), Map.put(state, :count, count)}
      ...> end
      iex> flow = AgentForge.new_stateful_flow([counter], store_name: :test_store)
      iex> {:ok, result1, _} = flow.(AgentForge.Signal.new(:inc, nil))
      iex> {:ok, result2, _} = flow.(AgentForge.Signal.new(:inc, nil))
      iex> result2.data > result1.data
      true
  """
  def new_stateful_flow(handlers, opts \\ []) do
    Runtime.configure_stateful(handlers, opts)
  end

  @doc """
  Processes a flow with execution limits.
  This can prevent long-running operations.

  ## Options

  * `:timeout_ms` - Maximum execution time in milliseconds (default: 30000)
  * `:collect_stats` - Whether to collect execution statistics (default: true)
  * `:return_stats` - Whether to return statistics in the result (default: false)

  ## Examples

      iex> handlers = [
      ...>   fn _signal, state -> {{:emit, AgentForge.Signal.new(:done, "Success")}, state} end
      ...> ]
      iex> {:ok, result, _} = AgentForge.process_with_limits(handlers, AgentForge.Signal.new(:test, "data"), %{})
      iex> result.data
      "Success"
  """
  @spec process_with_limits(
          # handler functions
          list(function()),
          # input signal
          Signal.t(),
          # initial state
          map(),
          # options
          keyword()
        ) ::
          {:ok, Signal.t() | term(), term()}
          | {:ok, Signal.t() | term(), term(), AgentForge.ExecutionStats.t()}
          | {:error, term(), term()}
          | {:error, term(), term(), AgentForge.ExecutionStats.t()}
  def process_with_limits(handlers, signal, initial_state, opts \\ []) do
    # Use Runtime.execute_with_limits instead of directly calling Flow.process_with_limits
    # This ensures proper state persistence between executions
    Runtime.execute_with_limits(
      handlers,
      signal,
      opts |> Keyword.put(:initial_state, initial_state)
    )
  end

  @doc """
  Gets statistics from the last flow execution.
  Returns nil if no flow has been executed yet or statistics collection was disabled.

  ## Examples

      iex> handlers = [fn signal, state -> {{:emit, signal}, state} end]
      iex> signal = AgentForge.Signal.new(:test, "data")
      iex> {:ok, _, _} = AgentForge.process_with_limits(handlers, signal, %{})
      iex> stats = AgentForge.get_last_execution_stats()
      iex> stats.steps
      1
  """
  def get_last_execution_stats do
    Runtime.get_last_execution_stats()
  end

  # Re-export commonly used functions from Signal module
  defdelegate new_signal(type, data, meta \\ %{}), to: Signal, as: :new
  defdelegate emit(type, data, meta \\ %{}), to: Signal
  defdelegate emit_many(signals), to: Signal
  defdelegate halt(value), to: Signal
end
