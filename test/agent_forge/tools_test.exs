defmodule AgentForge.ToolsTest do
  use ExUnit.Case
  doctest AgentForge.Tools

  alias AgentForge.{Signal, Tools}

  setup do
    registry = String.to_atom("test_registry_#{System.unique_integer()}")
    start_supervised!({Tools, name: registry})
    %{registry: registry}
  end

  describe "register/3 and get/2" do
    test "registers and retrieves tools", %{registry: registry} do
      assert :ok = Tools.register("uppercase", &String.upcase/1, registry)
      assert {:ok, tool} = Tools.get("uppercase", registry)
      assert tool.("hello") == "HELLO"
    end

    test "returns error for non-existent tools", %{registry: registry} do
      assert {:error, "Tool not found: nonexistent"} = Tools.get("nonexistent", registry)
    end

    test "validates tool function arity", %{registry: registry} do
      assert_raise FunctionClauseError, fn ->
        Tools.register("invalid", fn _, _ -> :ok end, registry)
      end
    end
  end

  describe "list/1" do
    test "returns sorted list of registered tools", %{registry: registry} do
      Tools.register("tool2", &String.downcase/1, registry)
      Tools.register("tool1", &String.upcase/1, registry)
      Tools.register("tool3", &String.reverse/1, registry)

      assert Tools.list(registry) == ["tool1", "tool2", "tool3"]
    end

    test "returns empty list when no tools registered", %{registry: registry} do
      assert Tools.list(registry) == []
    end
  end

  describe "execute/2" do
    test "executes tool and emits result", %{registry: registry} do
      Tools.register("add_one", fn n -> n + 1 end, registry)
      handler = Tools.execute("add_one", registry)
      signal = Signal.new(:number, 5)

      {{:emit, result}, _state} = handler.(signal, %{})

      assert result.type == :tool_result
      assert result.data == 6
      assert result.meta.tool == "add_one"
      assert result.meta.parent_trace_id == signal.meta.trace_id
    end

    test "handles tool execution errors", %{registry: registry} do
      Tools.register("fail", fn _ -> raise "Tool error" end, registry)
      handler = Tools.execute("fail", registry)
      signal = Signal.new(:test, "data")

      {{:emit, result}, _state} = handler.(signal, %{})

      assert result.type == :error
      assert result.data =~ "Tool error"
      assert result.meta.tool == "fail"
    end

    test "handles missing tools", %{registry: registry} do
      handler = Tools.execute("nonexistent", registry)
      signal = Signal.new(:test, "data")

      {{:emit, result}, _state} = handler.(signal, %{})

      assert result.type == :error
      assert result.data =~ "Tool not found"
    end
  end

  describe "execute_pipeline/2" do
    test "executes multiple tools in sequence", %{registry: registry} do
      # Register tools in reverse order to test order independence
      Tools.register("reverse", &String.reverse/1, registry)
      Tools.register("uppercase", &String.upcase/1, registry)

      pipeline = Tools.execute_pipeline(["uppercase", "reverse"], registry)
      signal = Signal.new(:text, "hello")

      {{:emit_many, results}, _state} = pipeline.(signal, %{})

      assert length(results) == 2
      uppercase_result = Enum.find(results, &(&1.meta.tool == "uppercase"))
      reverse_result = Enum.find(results, &(&1.meta.tool == "reverse"))

      assert uppercase_result.data == "HELLO"
      assert reverse_result.data == "olleh"
    end

    test "handles errors in pipeline", %{registry: registry} do
      Tools.register("uppercase", &String.upcase/1, registry)
      Tools.register("fail", fn _ -> raise "Pipeline error" end, registry)

      pipeline = Tools.execute_pipeline(["uppercase", "fail"], registry)
      signal = Signal.new(:text, "hello")

      {{:emit, result}, _state} = pipeline.(signal, %{})

      assert result.type == :error
      assert result.data =~ "Pipeline error"
    end

    test "handles missing tools in pipeline", %{registry: registry} do
      Tools.register("uppercase", &String.upcase/1, registry)

      pipeline = Tools.execute_pipeline(["uppercase", "nonexistent"], registry)
      signal = Signal.new(:text, "hello")

      {{:emit, result}, _state} = pipeline.(signal, %{})

      assert result.type == :error
      assert result.data =~ "Tool not found"
    end

    test "preserves metadata across pipeline", %{registry: registry} do
      Tools.register("step1", fn x -> x <> "_1" end, registry)
      Tools.register("step2", fn x -> x <> "_2" end, registry)

      pipeline = Tools.execute_pipeline(["step1", "step2"], registry)
      signal = Signal.new(:text, "data", %{custom: "value"})

      {{:emit_many, results}, _state} = pipeline.(signal, %{})

      Enum.each(results, fn result ->
        assert result.meta.parent_trace_id == signal.meta.trace_id
        assert result.meta.custom == "value"
      end)
    end
  end
end
