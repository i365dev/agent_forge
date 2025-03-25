defmodule AgentForge.Runtime do
  @moduledoc """
  Provides the runtime environment for executing flows in the AgentForge system.
  """

  alias AgentForge.{Flow, Signal, Store, Debug, ExecutionStats}

  @type runtime_options :: [
          debug: boolean(),
          name: String.t(),
          store_prefix: String.t(),
          store_name: atom(),
          max_steps: non_neg_integer() | :infinity,
          timeout: non_neg_integer() | :infinity,
          collect_stats: boolean(),
          return_stats: boolean()
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
  """
  @spec execute_with_limits(Flow.flow(), Signal.t(), map() | keyword(), runtime_options()) ::
          {:ok, Signal.t() | term(), term()}
          | {:ok, Signal.t() | term(), term(), ExecutionStats.t()}
          | {:error, term(), map()}
          | {:error, term(), map(), ExecutionStats.t()}
  def execute_with_limits(flow, signal, initial_state, opts \\ []) do
    # Ensure initial_state is a map
    initial_state = convert_to_map(initial_state)

    # Merge default options
    opts = merge_default_options(opts)

    # Initialize store and state
    {state_to_use, store_opts} = initialize_state(initial_state, opts)

    # Extract flow options from runtime options
    flow_opts = prepare_flow_options(opts)

    # Wrap with debug if enabled
    flow_to_use = maybe_wrap_debug(flow, opts)

    # Execute flow with limits and handle results
    try do
      case Flow.process_with_limits(flow_to_use, signal, state_to_use, flow_opts) do
        {:ok, result, final_state} = success ->
          maybe_update_store(store_opts, final_state)
          success

        {:ok, result, final_state, stats} = success ->
          maybe_update_store(store_opts, final_state)
          success

        {:error, reason, state} = error ->
          maybe_update_store(store_opts, state)
          error

        {:error, reason, state, stats} = error ->
          maybe_update_store(store_opts, state)
          error
      end
    catch
      kind, error ->
        error_msg = "Runtime error: #{inspect(kind)} - #{inspect(error)}"
        {:error, error_msg, initial_state}
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

  defp convert_to_map(value) do
    case value do
      map when is_map(map) -> map
      list when is_list(list) -> Map.new(list)
      _ -> Map.new()
    end
  end

  defp merge_default_options(opts) do
    Keyword.merge(
      [
        debug: false,
        name: "flow",
        store_prefix: "flow",
        max_steps: :infinity,
        timeout: :infinity,
        collect_stats: true,
        return_stats: false
      ],
      opts
    )
  end

  defp initialize_state(initial_state, opts) do
    case {Keyword.get(opts, :store_name), Keyword.get(opts, :store_key)} do
      {nil, _} ->
        {initial_state, nil}

      {_, nil} ->
        {initial_state, nil}

      {store_name, store_key} ->
        stored_state =
          case Store.get(store_name, store_key) do
            {:ok, state} -> Map.merge(state, initial_state)
            _ -> initial_state
          end

        {stored_state, {store_name, store_key}}
    end
  end

  defp prepare_flow_options(opts) do
    opts
    |> Keyword.take([:max_steps, :timeout, :collect_stats, :return_stats])
    |> Keyword.update(:max_steps, :infinity, &normalize_limit/1)
    |> Keyword.update(:timeout, :infinity, &normalize_limit/1)
  end

  defp maybe_wrap_debug(flow, opts) do
    if opts[:debug] do
      Debug.trace_flow(opts[:name], flow)
    else
      flow
    end
  end

  defp normalize_limit(:infinity), do: :infinity
  defp normalize_limit(value) when is_integer(value), do: value
  defp normalize_limit(_), do: :infinity

  defp maybe_update_store(nil, _state), do: :ok

  defp maybe_update_store({store_name, store_key}, state) do
    Store.put(store_name, store_key, state)
  end
end
