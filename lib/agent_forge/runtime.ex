defmodule AgentForge.Runtime do
  @moduledoc """
  Provides the runtime environment for executing flows in the AgentForge system.
  """

  alias AgentForge.{Debug, ExecutionStats, Flow, Signal, Store}

  @type runtime_options :: [
          collect_stats: boolean(),
          debug: boolean(),
          max_steps: non_neg_integer() | :infinity,
          name: String.t(),
          return_stats: boolean(),
          store_name: atom(),
          store_prefix: String.t(),
          timeout: non_neg_integer() | :infinity
        ]

  @spec execute(maybe_improper_list(), %{
          data: any(),
          meta: %{
            correlation_id: nil | binary(),
            custom: map(),
            source: nil | binary(),
            timestamp: nil | DateTime.t(),
            trace_id: nil | binary()
          },
          type: atom()
        }) :: {:error, any()} | {:ok, any(), any()}
  @doc """
  Executes a flow with the given signal and options.
  """
  @spec execute(Flow.flow(), Signal.t(), runtime_options()) ::
          {:ok, Signal.t() | term(), term()} | {:error, term()}
  def execute(flow, signal, opts \\ []) do
    opts = Keyword.merge([debug: false, name: "flow", store_prefix: "flow"], opts)

    # Initialize store if needed
    {initial_state, store_opts} =
      case {Keyword.get(opts, :store_key), Keyword.get(opts, :store_name, Store)} do
        {nil, _} ->
          {%{}, nil}

        {store_key, store_name} ->
          stored_state =
            case Store.get(store_name, store_key) do
              {:ok, state} -> state
              _ -> %{}
            end

          {stored_state, {store_name, store_key}}
      end

    # Wrap with debug if enabled
    flow =
      if opts[:debug] do
        Debug.trace_flow(opts[:name], flow)
      else
        flow
      end

    # Execute the flow
    case Flow.process(flow, signal, initial_state) do
      {:ok, result, final_state} ->
        # Update store if needed
        maybe_update_store(store_opts, final_state)
        {:ok, result, final_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets statistics from the last flow execution.
  """
  def get_last_execution_stats do
    Flow.get_last_execution_stats()
  end

  @doc """
  Creates a new runtime configuration for a flow.
  """
  @spec configure(Flow.flow(), runtime_options()) :: (Signal.t() ->
                                                        {:ok, term(), term()} | {:error, term()})
  def configure(flow, opts \\ []) do
    fn signal -> execute(flow, signal, opts) end
  end

  @doc """
  Creates a new runtime configuration that maintains state between executions.
  """
  @spec configure_stateful(Flow.flow(), runtime_options()) ::
          (Signal.t() -> {:ok, term(), term()} | {:error, term()})
  def configure_stateful(flow, opts \\ []) do
    # Generate a unique store name if not provided
    store_name =
      Keyword.get_lazy(opts, :store_name, fn ->
        :"store_#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}"
      end)

    # Start the store if needed
    _ = ensure_store_started(store_name)

    # Generate a unique store key if not provided
    opts =
      opts
      |> Keyword.put(:store_name, store_name)
      |> Keyword.put_new_lazy(:store_key, fn ->
        prefix = Keyword.get(opts, :store_prefix, "flow")
        :"#{prefix}_#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}"
      end)

    configure(flow, opts)
  end

  @doc """
  Executes a flow with execution limits.

  Enforces limits on execution (maximum steps and timeout) to prevent
  infinite loops and long-running processes. Integrates with Store for
  state persistence between executions.

  ## Options
    * `:timeout_ms` - Maximum execution time in milliseconds (default: 30000)
    * `:collect_stats` - Whether to collect execution statistics (default: true)
    * `:return_stats` - Whether to include stats in the return value (default: false)
    * `:debug` - Whether to enable debugging (default: false)
    * `:name` - Name for debugging output (default: "flow")
    * `:store_prefix` - Prefix for store keys (default: "flow")
    * `:store_name` - Name of the store to use
    * `:store_key` - Key within the store to access state
    * `:initial_state` - Initial state to use for execution
  """
  @spec execute_with_limits(Flow.flow(), Signal.t(), runtime_options()) ::
          {:ok, Signal.t() | term(), term()}
          | {:ok, Signal.t() | term(), term(), ExecutionStats.t()}
          | {:error, term(), term()}
          | {:error, term(), term(), ExecutionStats.t()}
  def execute_with_limits(flow, signal, opts \\ []) do
    # Merge default options
    opts =
      Keyword.merge(
        [
          debug: false,
          name: "flow",
          store_prefix: "flow",
          timeout_ms: 30_000,
          collect_stats: true,
          return_stats: false
        ],
        opts
      )

    # Initialize store if needed
    # Determine initial state and store options
    initial_state = Keyword.get(opts, :initial_state)
    store_name = Keyword.get(opts, :store_name)
    store_key = Keyword.get(opts, :store_key)

    # Initialize default values
    {initial_state, store_opts} =
      resolve_initial_state_and_store(initial_state, store_name, store_key)

    # Wrap with debug if enabled
    flow_to_use =
      if opts[:debug] do
        Debug.trace_flow(opts[:name], flow)
      else
        flow
      end

    # Execute the flow with limits
    flow_opts = [
      timeout_ms: opts[:timeout_ms],
      collect_stats: opts[:collect_stats],
      return_stats: opts[:return_stats]
    ]

    # Call Flow.process_with_limits with the appropriate options
    result = Flow.process_with_limits(flow_to_use, signal, initial_state, flow_opts)

    # Handle the different result formats and update store if needed
    case result do
      # Success with statistics
      {:ok, output, final_state, stats} ->
        maybe_update_store(store_opts, final_state)
        {:ok, output, final_state, stats}

      # Success without statistics
      {:ok, output, final_state} ->
        maybe_update_store(store_opts, final_state)
        {:ok, output, final_state}

      # Error with state and statistics
      {:error, reason, final_state, stats} ->
        maybe_update_store(store_opts, final_state)
        {:error, reason, final_state, stats}

      # Error with state (for handler errors)
      {:error, reason, final_state} ->
        maybe_update_store(store_opts, final_state)
        {:error, reason, final_state}
    end
  end

  # Private helpers

  defp ensure_store_started(store_name) do
    case Store.start_link(name: store_name) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
      error -> raise "Failed to start store: #{inspect(error)}"
    end
  end

  # Helper function to update store with cleaned state
  defp maybe_update_store(nil, _state), do: :ok

  defp maybe_update_store({store_name, store_key}, state) do
    # Remove internal state keys to avoid polluting user state
    clean_state =
      state
      |> Map.delete(:store_name)
      |> Map.delete(:store_key)
      |> Map.delete(:max_steps)
      |> Map.delete(:timeout)
      |> Map.delete(:return_stats)

    Store.put(store_name, store_key, clean_state)
  end

  # Resolves the initial state and store options based on inputs
  defp resolve_initial_state_and_store(initial_state, store_name, store_key) do
    cond do
      # When initial state is explicitly provided
      not is_nil(initial_state) ->
        store_opts = resolve_store_options(store_name, store_key)
        {initial_state, store_opts}

      # When store information is not complete
      is_nil(store_name) or is_nil(store_key) ->
        {%{}, nil}

      # When we need to retrieve from store
      true ->
        stored_state = fetch_from_store(store_name, store_key)
        {stored_state, {store_name, store_key}}
    end
  end

  # Helper to determine store options
  defp resolve_store_options(store_name, store_key) do
    case {store_name, store_key} do
      {nil, _} -> nil
      {_, nil} -> nil
      {name, key} -> {name, key}
    end
  end

  # Helper to fetch state from store
  defp fetch_from_store(store_name, store_key) do
    case Store.get(store_name, store_key) do
      {:ok, state} -> state
      _ -> %{}
    end
  end
end
