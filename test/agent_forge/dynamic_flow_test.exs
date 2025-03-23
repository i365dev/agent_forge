defmodule AgentForge.DynamicFlowTest do
  use ExUnit.Case
  doctest AgentForge.DynamicFlow

  alias AgentForge.{DynamicFlow, Signal}

  describe "select_flow/1" do
    test "selects and executes different flows based on signal type" do
      selector =
        DynamicFlow.select_flow(fn signal, _ ->
          case signal.type do
            :text -> [fn s, st -> {Signal.emit(:processed_text, String.upcase(s.data)), st} end]
            :number -> [fn s, st -> {Signal.emit(:processed_number, s.data * 2), st} end]
            _ -> [fn s, st -> {Signal.emit(:unknown, s.data), st} end]
          end
        end)

      text_signal = Signal.new(:text, "hello")
      {{:emit, text_result}, _} = selector.(text_signal, %{})
      assert text_result.type == :processed_text
      assert text_result.data == "HELLO"

      number_signal = Signal.new(:number, 5)
      {{:emit, number_result}, _} = selector.(number_signal, %{})
      assert number_result.type == :processed_number
      assert number_result.data == 10
    end

    test "handles errors in flow selection" do
      selector = DynamicFlow.select_flow(fn _, _ -> raise "Selection error" end)
      signal = Signal.new(:test, "data")
      {{:emit, result}, _} = selector.(signal, %{})

      assert result.type == :error
      assert result.data =~ "Selection error"
    end

    test "validates flow selector returns a list" do
      selector = DynamicFlow.select_flow(fn _, _ -> :not_a_list end)
      signal = Signal.new(:test, "data")
      {{:emit, result}, _} = selector.(signal, %{})

      assert result.type == :error
      assert result.data =~ "must return a list"
    end
  end

  describe "append_handlers/1" do
    test "appends handlers based on signal content" do
      selector = fn signal, _ ->
        if String.contains?(signal.data, "urgent") do
          [fn _, st -> {Signal.emit(:priority, "High"), st} end]
        else
          [fn _, st -> {Signal.emit(:priority, "Normal"), st} end]
        end
      end

      handler = DynamicFlow.append_handlers(selector)

      urgent_signal = Signal.new(:message, "urgent task")
      {{:emit, urgent_result}, _} = handler.(urgent_signal, %{})
      assert urgent_result.type == :priority
      assert urgent_result.data == "High"

      normal_signal = Signal.new(:message, "regular task")
      {{:emit, normal_result}, _} = handler.(normal_signal, %{})
      assert normal_result.type == :priority
      assert normal_result.data == "Normal"
    end

    test "handles errors in handler selection" do
      selector = fn _, _ -> raise "Handler selection error" end
      handler = DynamicFlow.append_handlers(selector)
      signal = Signal.new(:test, "data")
      {{:emit, result}, _} = handler.(signal, %{})

      assert result.type == :error
      assert result.data =~ "Handler selection error"
    end
  end

  describe "subflow/1" do
    test "creates and executes dynamic subflows" do
      creator = fn signal, _ ->
        case signal.type do
          :validate -> [fn s, st -> {Signal.emit(:validated, s.data <> "_valid"), st} end]
          :process -> [fn s, st -> {Signal.emit(:processed, s.data <> "_done"), st} end]
        end
      end

      handler = DynamicFlow.subflow(creator)

      validate_signal = Signal.new(:validate, "test")
      {{:emit, validate_result}, _} = handler.(validate_signal, %{})
      assert validate_result.type == :validated
      assert validate_result.data == "test_valid"

      process_signal = Signal.new(:process, "task")
      {{:emit, process_result}, _} = handler.(process_signal, %{})
      assert process_result.type == :processed
      assert process_result.data == "task_done"
    end

    test "handles errors in subflow creation" do
      creator = fn _, _ -> raise "Subflow creation error" end
      handler = DynamicFlow.subflow(creator)
      signal = Signal.new(:test, "data")
      {{:emit, result}, _} = handler.(signal, %{})

      assert result.type == :error
      assert result.data =~ "Subflow creation error"
    end
  end

  describe "merge_flows/1" do
    test "combines multiple flows and collects results" do
      flows = [
        [fn s, st -> {Signal.emit(:result1, s.data <> "_1"), st} end],
        [fn s, st -> {Signal.emit(:result2, s.data <> "_2"), st} end],
        [fn s, st -> {Signal.emit(:result3, s.data <> "_3"), st} end]
      ]

      merger = DynamicFlow.merge_flows(flows)
      signal = Signal.new(:start, "data")
      {{:emit_many, results}, _} = merger.(signal, %{})

      assert length(results) == 3
      assert Enum.map(results, & &1.type) == [:result1, :result2, :result3]
      assert Enum.map(results, & &1.data) == ["data_1", "data_2", "data_3"]
    end

    test "maintains state across merged flows" do
      flows = [
        [
          fn _, st ->
            {Signal.emit(:count, Map.get(st, :count, 0) + 1), Map.put(st, :count, 1)}
          end
        ],
        [
          fn _, st ->
            {Signal.emit(:count, Map.get(st, :count, 0) + 1), Map.put(st, :count, 2)}
          end
        ]
      ]

      merger = DynamicFlow.merge_flows(flows)
      signal = Signal.new(:start, "data")
      {{:emit_many, results}, final_state} = merger.(signal, %{})

      assert Enum.map(results, & &1.data) == [1, 2]
      assert final_state.count == 2
    end

    test "handles errors in merged flows" do
      flows = [
        [fn s, st -> {Signal.emit(:result1, s.data), st} end],
        [fn _, _ -> raise "Flow error" end]
      ]

      merger = DynamicFlow.merge_flows(flows)
      signal = Signal.new(:start, "data")
      {{:emit, result}, _} = merger.(signal, %{})

      assert result.type == :error
    end
  end
end
