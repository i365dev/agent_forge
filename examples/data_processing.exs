# Data Processing Workflow Example
#
# This example demonstrates a simple data processing pipeline using AgentForge primitives
# to validate, transform, and aggregate data.
#
# To run: elixir examples/data_processing.exs

Code.require_file("lib/agent_forge.ex")
Code.require_file("lib/agent_forge/signal.ex")
Code.require_file("lib/agent_forge/flow.ex")
Code.require_file("lib/agent_forge/primitives.ex")

defmodule DataProcessing do
  alias AgentForge.{Flow, Signal, Primitives}

  def process_orders do
    # Define data validation
    validate_order = Primitives.transform(fn order ->
      cond do
        is_nil(order.id) -> raise "Order ID is required"
        order.amount <= 0 -> raise "Invalid order amount"
        true -> order
      end
    end)

    # Transform orders to add tax
    add_tax = Primitives.transform(fn order ->
      tax = order.amount * 0.1
      Map.put(order, :total, order.amount + tax)
    end)

    # Branch based on order size
    route_order = Primitives.branch(
      fn signal, _ -> signal.data.total > 1000 end,
      [fn signal, state -> {Signal.emit(:large_order, signal.data), state} end],
      [fn signal, state -> {Signal.emit(:standard_order, signal.data), state} end]
    )

    # Create notification for large orders
    notify_large_order = Primitives.notify(
      [:console],
      format: fn order -> "Large order received: ##{order.id} (Total: $#{order.total})" end
    )

    # Compose the workflow
    large_order_flow = [
      fn signal, state -> {Signal.emit(:processing, signal.data), state} end,
      notify_large_order
    ]

    standard_order_flow = [
      fn signal, state -> {Signal.emit(:processing, signal.data), state} end
    ]

    # Define sample orders
    orders = [
      %{id: 1, amount: 500},
      %{id: 2, amount: 1200},
      %{id: 3, amount: 800}
    ]

    # Process orders
    Enum.each(orders, fn order ->
      # Create initial signal
      signal = Signal.new(:order, order)
      state = %{}

      # Process through validation and tax calculation
      {:ok, validated_signal, state1} = Flow.process([validate_order, add_tax], signal, state)

      # Route and process based on order size
      case Flow.process([route_order], validated_signal, state1) do
        {:ok, %{type: :large_order} = signal, state2} ->
          Flow.process(large_order_flow, signal, state2)

        {:ok, %{type: :standard_order} = signal, state2} ->
          Flow.process(standard_order_flow, signal, state2)
      end
    end)
  end
end

# Run the example
DataProcessing.process_orders()
