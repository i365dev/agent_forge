defmodule AgentForge.DynamicFlow do
  @moduledoc """
  Provides functions for dynamic flow creation and modification at runtime.
  Allows flows to adapt based on signal content and execution context.
  """

  alias AgentForge.{Flow, Signal}

  @doc """
  Creates a handler that dynamically selects a flow based on signal content.
  The flow_selector function should return a list of handlers.

  ## Examples

      iex> selector = AgentForge.DynamicFlow.select_flow(fn signal, _ ->
      ...>   case signal.type do
      ...>     :text -> [fn _s, st -> {AgentForge.Signal.emit(:processed_text, signal.data), st} end]
      ...>     :number -> [fn _s, st -> {AgentForge.Signal.emit(:processed_number, signal.data * 2), st} end]
      ...>     _ -> [fn _s, st -> {AgentForge.Signal.emit(:unknown, signal.data), st} end]
      ...>   end
      ...> end)
      iex> signal = AgentForge.Signal.new(:number, 5)
      iex> {{:emit, result}, _state} = selector.(signal, %{})
      iex> result.data
      10
  """
  def select_flow(flow_selector) when is_function(flow_selector, 2) do
    fn signal, state ->
      try do
        selected_flow = flow_selector.(signal, state)

        if not is_list(selected_flow) do
          raise "Flow selector must return a list of handlers"
        end

        case Flow.process(selected_flow, signal, state) do
          {:ok, result, new_state} -> {{:emit, result}, new_state}
          {:error, reason} -> {{:emit, Signal.new(:error, reason)}, state}
        end
      rescue
        e ->
          {{:emit, Signal.new(:error, "Flow selection error: #{Exception.message(e)}")}, state}
      end
    end
  end

  @doc """
  Creates a handler that appends additional handlers based on signal content.
  The handlers_selector function should return a list of handlers to append.

  ## Examples

      iex> selector = fn signal, _ ->
      ...>   if String.contains?(signal.data, "urgent") do
      ...>     [fn _s, st -> {AgentForge.Signal.emit(:priority, "High priority"), st} end]
      ...>   else
      ...>     [fn _s, st -> {AgentForge.Signal.emit(:priority, "Normal priority"), st} end]
      ...>   end
      ...> end
      iex> handler = AgentForge.DynamicFlow.append_handlers(selector)
      iex> signal = AgentForge.Signal.new(:message, "urgent task")
      iex> {{:emit, result}, _state} = handler.(signal, %{})
      iex> result.data
      "High priority"
  """
  def append_handlers(handlers_selector) when is_function(handlers_selector, 2) do
    fn signal, state ->
      try do
        additional_handlers = handlers_selector.(signal, state)

        if not is_list(additional_handlers) do
          raise "Handlers selector must return a list of handlers"
        end

        case Flow.process(additional_handlers, signal, state) do
          {:ok, result, new_state} -> {{:emit, result}, new_state}
          {:error, reason} -> {{:emit, Signal.new(:error, reason)}, state}
        end
      rescue
        e ->
          {{:emit, Signal.new(:error, "Handler selection error: #{Exception.message(e)}")}, state}
      end
    end
  end

  @doc """
  Creates a handler that dynamically creates and executes a subflow.
  The subflow_creator function should return a complete flow configuration.

  ## Examples

      iex> creator = fn signal, _ ->
      ...>   case signal.type do
      ...>     :validate -> [
      ...>       fn _s, st -> {AgentForge.Signal.emit(:validated, signal.data), st} end
      ...>     ]
      ...>     :process -> [
      ...>       fn _s, st -> {AgentForge.Signal.emit(:processed, signal.data), st} end
      ...>     ]
      ...>   end
      ...> end
      iex> handler = AgentForge.DynamicFlow.subflow(creator)
      iex> signal = AgentForge.Signal.new(:validate, "test")
      iex> {{:emit, result}, _state} = handler.(signal, %{})
      iex> result.type == :validated
      true
  """
  def subflow(subflow_creator) when is_function(subflow_creator, 2) do
    fn signal, state ->
      try do
        flow = subflow_creator.(signal, state)

        if not is_list(flow) do
          raise "Subflow creator must return a list of handlers"
        end

        case Flow.process(flow, signal, state) do
          {:ok, result, new_state} -> {{:emit, result}, new_state}
          {:error, reason} -> {{:emit, Signal.new(:error, reason)}, state}
        end
      rescue
        e ->
          {{:emit, Signal.new(:error, "Subflow creation error: #{Exception.message(e)}")}, state}
      end
    end
  end

  @doc """
  Creates a flow merger that combines multiple flows into one.
  Each flow is executed in sequence with the same input signal.
  Results are collected and emitted as a batch.

  ## Examples

      iex> flows = [
      ...>   [fn _s, st -> {AgentForge.Signal.emit(:result1, "data_1"), st} end],
      ...>   [fn _s, st -> {AgentForge.Signal.emit(:result2, "data_2"), st} end]
      ...> ]
      iex> merger = AgentForge.DynamicFlow.merge_flows(flows)
      iex> signal = AgentForge.Signal.new(:start, "data")
      iex> {{:emit_many, results}, _state} = merger.(signal, %{})
      iex> length(results) == 2
      true
  """
  def merge_flows(flows) when is_list(flows) do
    fn signal, state ->
      try do
        {results, final_state} =
          Enum.reduce(flows, {[], state}, fn flow, {results, current_state} ->
            case Flow.process(flow, signal, current_state) do
              {:ok, result, new_state} -> {[result | results], new_state}
              {:error, reason} -> raise(reason)
            end
          end)

        {{:emit_many, Enum.reverse(results)}, final_state}
      rescue
        e ->
          error = "Tool pipeline error: #{Exception.message(e)}"
          {{:emit, Signal.new(:error, error)}, state}
      end
    end
  end
end
