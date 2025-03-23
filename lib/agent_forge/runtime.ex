defmodule AgentForge.Runtime do
  @moduledoc """
  Provides the runtime environment for executing flows in the AgentForge system.
  """

  alias AgentForge.{Flow, Signal, Store, Debug}

  @type runtime_options :: [
          debug: boolean(),
          name: String.t(),
          store_prefix: String.t(),
          store_name: atom()
        ]

  @doc """
  Executes a flow with the given signal and options.
  Returns the result of processing the flow.

  ## Options

  * `:debug` - Enables debug logging (default: false)
  * `:name` - Name for the flow execution (default: "flow")
  * `:store_prefix` - Prefix for store keys (default: "flow")
  * `:store_name` - Name of the store to use (optional)

  ## Examples

      iex> handler = fn signal, state ->
      ...>   {AgentForge.Signal.emit(:done, "Processed: " <> signal.data), state}
      ...> end
      iex> {:ok, result, _state} = AgentForge.Runtime.execute([handler],
      ...>   AgentForge.Signal.new(:start, "test"),
      ...>   debug: true
      ...> )
      iex> result.data
      "Processed: test"
  """
  @spec execute(Flow.flow(), Signal.t(), runtime_options()) ::
          {:ok, Signal.t() | term(), term()} | {:error, term()}
  def execute(flow, signal, opts \\ []) do
    opts = Keyword.merge([debug: false, name: "flow", store_prefix: "flow"], opts)

    # Initialize store if needed
    initial_state =
      case {Keyword.get(opts, :store_key), Keyword.get(opts, :store_name, Store)} do
        {nil, _} ->
          %{}

        {store_key, store_name} ->
          case Store.get(store_name, store_key) do
            {:ok, stored_state} -> stored_state
            _ -> %{}
          end
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
        case {Keyword.get(opts, :store_key), Keyword.get(opts, :store_name, Store)} do
          {nil, _} ->
            {:ok, result, final_state}

          {store_key, store_name} ->
            Store.put(store_name, store_key, final_state)
            {:ok, result, final_state}
        end

      error ->
        error
    end
  end

  @doc """
  Creates a new runtime configuration for a flow.
  This allows storing configuration that can be reused for multiple executions.

  ## Examples

      iex> handler = fn signal, state ->
      ...>   {AgentForge.Signal.emit(:done, signal.data), state}
      ...> end
      iex> runtime = AgentForge.Runtime.configure([handler], debug: true, name: "test_flow")
      iex> is_function(runtime, 1)
      true
  """
  @spec configure(Flow.flow(), runtime_options()) :: (Signal.t() ->
                                                        {:ok, term(), term()} | {:error, term()})
  def configure(flow, opts \\ []) do
    fn signal -> execute(flow, signal, opts) end
  end

  @doc """
  Creates a new runtime configuration that maintains state between executions.
  Similar to configure/2 but automatically stores and retrieves state.

  ## Examples

      iex> increment = fn _signal, state ->
      ...>   count = Map.get(state, :count, 0) + 1
      ...>   {AgentForge.Signal.emit(:count, count), Map.put(state, :count, count)}
      ...> end
      iex> runtime = AgentForge.Runtime.configure_stateful([increment],
      ...>   store_key: :counter,
      ...>   debug: true
      ...> )
      iex> is_function(runtime, 1)
      true
  """
  @spec configure_stateful(Flow.flow(), runtime_options()) ::
          (Signal.t() -> {:ok, term(), term()} | {:error, term()})
  def configure_stateful(flow, opts \\ []) do
    # Generate a unique store name if not provided
    store_name =
      Keyword.get_lazy(opts, :store_name, fn ->
        :"store_#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}"
      end)

    # Generate a unique store key if not provided
    opts =
      opts
      |> Keyword.put(:store_name, store_name)
      |> Keyword.put_new_lazy(:store_key, fn ->
        prefix = Keyword.get(opts, :store_prefix, "flow")
        :"#{prefix}_#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}"
      end)

    # Don't try to start the store if it's already started
    case Process.whereis(store_name) do
      nil ->
        case Store.start_link(name: store_name) do
          {:ok, _pid} -> configure(flow, opts)
          {:error, {:already_started, _pid}} -> configure(flow, opts)
          error -> error
        end

      _pid ->
        configure(flow, opts)
    end
  end
end
