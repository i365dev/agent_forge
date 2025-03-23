defmodule AgentForge.FlowTest do
  use ExUnit.Case
  doctest AgentForge.Flow

  alias AgentForge.{Flow, Signal}

  describe "process/3" do
    test "processes a single handler" do
      handler = fn signal, state ->
        {Signal.emit(:processed, signal.data), state}
      end

      signal = Signal.new(:test, "data")
      {:ok, result, _state} = Flow.process([handler], signal, %{})

      assert result.type == :processed
      assert result.data == "data"
    end

    test "processes multiple handlers in sequence" do
      handler1 = fn signal, state ->
        {Signal.emit(:step1, "#{signal.data}_1"), state}
      end

      handler2 = fn signal, state ->
        {Signal.emit(:step2, "#{signal.data}_2"), state}
      end

      signal = Signal.new(:test, "data")
      {:ok, result, _state} = Flow.process([handler1, handler2], signal, %{})

      assert result.type == :step2
      assert result.data == "data_1_2"
    end

    test "handles state updates" do
      handler1 = fn signal, state ->
        new_state = Map.put(state, :value1, signal.data)
        {Signal.emit(:step1, signal.data), new_state}
      end

      handler2 = fn signal, state ->
        value = Map.get(state, :value1, "")
        {Signal.emit(:step2, "#{value}_#{signal.data}"), state}
      end

      signal = Signal.new(:test, "data")
      {:ok, result, final_state} = Flow.process([handler1, handler2], signal, %{})

      assert result.type == :step2
      assert result.data == "data_data"
      assert final_state.value1 == "data"
    end

    test "handles :skip result" do
      handler = fn _signal, state ->
        {:skip, state}
      end

      signal = Signal.new(:test, "data")
      {:ok, nil, state} = Flow.process([handler], signal, %{})

      assert state == %{}
    end

    test "handles :halt result" do
      handler1 = fn _signal, state ->
        {Signal.halt("stopped"), state}
      end

      handler2 = fn signal, state ->
        {Signal.emit(:never_reached, signal.data), state}
      end

      signal = Signal.new(:test, "data")
      {:ok, "stopped", state} = Flow.process([handler1, handler2], signal, %{})

      assert state == %{}
    end

    test "handles errors gracefully" do
      handler = fn _signal, _state ->
        raise "Oops"
      end

      signal = Signal.new(:test, "data")
      {:error, message} = Flow.process([handler], signal, %{})

      assert message =~ "Flow processing error"
    end
  end

  describe "helper functions" do
    test "always_emit/3 creates a constant handler" do
      handler = Flow.always_emit(:done, "success")
      {result, state} = handler.(nil, %{})

      assert match?({:emit, %{type: :done, data: "success"}}, result)
      assert state == %{}
    end

    test "filter_type/2 filters signals by type" do
      inner_handler = fn signal, state ->
        {Signal.emit(:processed, signal.data), state}
      end

      handler = Flow.filter_type(:test, inner_handler)

      test_signal = Signal.new(:test, "data")
      other_signal = Signal.new(:other, "data")

      {test_result, _} = handler.(test_signal, %{})
      {other_result, _} = handler.(other_signal, %{})

      assert match?({:emit, %{type: :processed}}, test_result)
      assert other_result == :skip
    end

    test "store_in_state/1 updates state with signal data" do
      handler = Flow.store_in_state(:last_message)
      signal = Signal.new(:test, "data")
      {result, state} = handler.(signal, %{})

      assert result == :skip
      assert state.last_message == "data"
    end
  end
end
