defmodule AgentForge.ConfigTest do
  use ExUnit.Case

  alias AgentForge.{Config, Signal, Tools}

  setup do
    # Register tools in default registry
    Tools.register("uppercase", &String.upcase/1)
    Tools.register("append_test", fn s -> "#{s}_test" end)
    Tools.register("count_chars", &String.length/1)

    # Clean up after each test
    on_exit(fn ->
      # We just need to stop the process to clean up all registrations
      if Process.whereis(AgentForge.Tools) do
        Process.exit(Process.whereis(AgentForge.Tools), :normal)
      end
    end)

    :ok
  end

  describe "load_from_string/1" do
    test "loads a simple transform workflow" do
      yaml = ~s"""
      flow:
        - type: transform
          fn: upcase
      """

      flow = Config.load_from_string(yaml)
      assert is_function(flow, 1)

      # Test flow execution
      signal = Signal.new(:text, "hello")
      {:ok, result, _} = flow.(signal)

      assert result.type == :text
      assert result.data == "HELLO"
    end

    test "loads a workflow with branching" do
      yaml = ~s"""
      flow:
        - type: branch
          condition: String.length(data) > 3
          then:
            - type: transform
              fn: data <> "_long"
          else:
            - type: transform
              fn: data <> "_short"
      """

      flow = Config.load_from_string(yaml)

      # Test long text
      long_signal = Signal.new(:text, "hello")
      {:ok, long_result, _} = flow.(long_signal)
      assert long_result.data == "hello_long"

      # Test short text
      short_signal = Signal.new(:text, "hi")
      {:ok, short_result, _} = flow.(short_signal)
      assert short_result.data == "hi_short"
    end

    test "loads a workflow with tool execution" do
      yaml = ~s"""
      flow:
        - type: tool
          name: uppercase
        - type: tool
          name: append_test
      """

      flow = Config.load_from_string(yaml)

      signal = Signal.new(:text, "hello")
      {:ok, result, _} = flow.(signal)

      # Expected result: "HELLO" -> "HELLO_test"
      assert result.type == :tool_result
      assert result.data == "HELLO_test"
    end

    test "loads a workflow with loop processing" do
      yaml = ~s"""
      flow:
        - type: loop
          action:
            - type: transform
              fn: String.upcase(data)
      """

      flow = Config.load_from_string(yaml)

      signal = Signal.new(:list, ["a", "b", "c"])
      {:ok, result, _} = flow.(signal)

      # The loop should have processed each item and the result will be a list of signals
      assert Enum.any?([result.type], fn type -> type in [:loop_item, :item] end)
      assert result.data in ["A", "B", "C"]  # Should be one of the uppercase items
    end

    test "handles JSON format" do
      json = ~s"""
      {
        "flow": [
          {
            "type": "transform",
            "fn": "String.upcase(data)"
          }
        ]
      }
      """

      flow = Config.load_from_string(json)

      signal = Signal.new(:text, "hello")
      {:ok, result, _} = flow.(signal)

      assert result.data == "HELLO"
    end

    test "handles invalid configurations" do
      # Missing flow field
      yaml1 = ~s"""
      steps:
        - type: transform
          fn: upcase
      """

      flow1 = Config.load_from_string(yaml1)
      {:error, error1} = flow1.(Signal.new(:text, "test"))
      assert error1 =~ "Missing flow definition"

      # Invalid step type
      yaml2 = ~s"""
      flow:
        - type: invalid_type
          value: test
      """

      flow2 = Config.load_from_string(yaml2)
      {:error, error2} = flow2.(Signal.new(:text, "test"))
      assert error2 =~ "Unknown step type"
    end

    test "handles complex nested workflows" do
      yaml = ~s"""
      flow:
        - type: branch
          condition: String.length(data) > 3
          then:
            - type: sequence
              steps:
                - type: transform
                  fn: upcase
                - type: tool
                  name: append_test
          else:
            - type: tool
              name: count_chars
      """

      flow = Config.load_from_string(yaml)

      # Long text should go through then branch: upcase -> append_test
      long_signal = Signal.new(:text, "hello")
      {:ok, long_result, _} = flow.(long_signal)
      assert long_result.data == "HELLO_test"

      # Short text should go through else branch: count_chars
      short_signal = Signal.new(:text, "hi")
      {:ok, short_result, _} = flow.(short_signal)
      assert short_result.data == 2
    end
  end

  describe "load_from_file/1" do
    test "loads a workflow from a file" do
      # Create a temporary file
      file_path = "test/fixtures/temp_workflow.yaml"
      File.mkdir_p!(Path.dirname(file_path))

      yaml = ~s"""
      flow:
        - type: transform
          fn: upcase
      """

      File.write!(file_path, yaml)

      flow = Config.load_from_file(file_path)
      assert is_function(flow, 1)

      signal = Signal.new(:text, "hello")
      {:ok, result, _} = flow.(signal)
      assert result.data == "HELLO"

      # Cleanup
      File.rm!(file_path)
    end

    test "handles file read errors" do
      flow = Config.load_from_file("nonexistent_file.yaml")
      {:error, message} = flow.(Signal.new(:test, "data"))
      assert message =~ "Failed to read file"
    end
  end
end
