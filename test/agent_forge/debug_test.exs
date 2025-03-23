defmodule AgentForge.DebugTest do
  use ExUnit.Case
  doctest AgentForge.Debug
  import ExUnit.CaptureLog

  alias AgentForge.{Debug, Signal}

  # Helper to strip ANSI color codes from log output
  defp strip_color(string) do
    String.replace(string, ~r/\e\[[0-9;]*m/, "")
  end

  describe "trace_handler/2" do
    test "wraps handler with debug logging" do
      handler = fn signal, state ->
        {Signal.emit(:processed, signal.data), state}
      end

      debug_handler = Debug.trace_handler("test", handler)
      signal = Signal.new(:test, "data")

      log =
        strip_color(
          capture_log(fn ->
            {result, _state} = debug_handler.(signal, %{})
            assert match?({:emit, %{type: :processed, data: "data"}}, result)
          end)
        )

      assert log =~ "[test] Processing signal"
      assert log =~ "Type: :test"
      assert log =~ "Data: \"data\""
      assert log =~ "[test] Handler result"
      assert log =~ "Emit: :processed"
    end

    test "logs correlation information when present" do
      handler = fn signal, state ->
        {Signal.emit(:processed, signal.data), state}
      end

      debug_handler = Debug.trace_handler("test", handler)
      parent = Signal.new(:parent, "parent")
      child = Signal.correlate(Signal.new(:child, "child"), parent)

      log =
        strip_color(
          capture_log(fn ->
            debug_handler.(child, %{})
          end)
        )

      assert log =~ ~s(Correlation: "#{child.meta.correlation_id}")
      assert log =~ ~s(Trace: "#{child.meta.trace_id}")
    end
  end

  describe "trace_flow/2" do
    test "wraps all handlers in a flow with debug logging" do
      handlers = [
        fn signal, state -> {Signal.emit(:step1, signal.data), state} end,
        fn signal, state -> {Signal.emit(:step2, "#{signal.data}_2"), state} end
      ]

      debug_flow = Debug.trace_flow("test_flow", handlers)
      signal = Signal.new(:start, "data")

      log =
        strip_color(
          capture_log(fn ->
            results =
              Enum.map(debug_flow, fn handler ->
                handler.(signal, %{})
              end)

            assert length(results) == 2
          end)
        )

      assert log =~ "[test_flow[0]]"
      assert log =~ "[test_flow[1]]"
      assert log =~ "Type: :start"
      assert log =~ "Emit: :step1"
      assert log =~ "Emit: :step2"
    end

    test "handles handlers with options" do
      handlers = [
        {fn signal, state -> {Signal.emit(:step1, signal.data), state} end, [retry: true]},
        fn signal, state -> {Signal.emit(:step2, signal.data), state} end
      ]

      debug_flow = Debug.trace_flow("test_flow", handlers)
      assert length(debug_flow) == 2

      [handler1, handler2] = debug_flow
      assert is_tuple(handler1)
      assert is_function(elem(handler1, 0))
      assert is_list(elem(handler1, 1))
      assert is_function(handler2)
    end
  end

  describe "log_signal_processing/2" do
    test "logs signal details" do
      signal = Signal.new(:test, %{key: "value"})

      log =
        strip_color(
          capture_log(fn ->
            Debug.log_signal_processing("context", signal)
          end)
        )

      assert log =~ "[context]"
      assert log =~ "Type: :test"
      assert log =~ ~s(Data: %{key: "value"})
      assert log =~ "Trace: \"#{signal.meta.trace_id}\""
    end
  end

  describe "result formatting" do
    test "formats emit result" do
      signal = Signal.new(:test, "data")

      handler =
        Debug.trace_handler("test", fn _, state ->
          {Signal.emit(:done, "success"), state}
        end)

      log =
        strip_color(
          capture_log(fn ->
            handler.(signal, %{})
          end)
        )

      assert log =~ "Emit: :done -> \"success\""
    end

    test "formats emit_many result" do
      signal = Signal.new(:test, "data")

      handler =
        Debug.trace_handler("test", fn _, state ->
          {Signal.emit_many([
             {:step1, "data1"},
             {:step2, "data2"}
           ]), state}
        end)

      log =
        strip_color(
          capture_log(fn ->
            handler.(signal, %{})
          end)
        )

      assert log =~ "Emit Many:"
      assert log =~ ":step1 -> \"data1\""
      assert log =~ ":step2 -> \"data2\""
    end

    test "formats halt result" do
      signal = Signal.new(:test, "data")

      handler =
        Debug.trace_handler("test", fn _, state ->
          {Signal.halt("stopped"), state}
        end)

      log =
        strip_color(
          capture_log(fn ->
            handler.(signal, %{})
          end)
        )

      assert log =~ "Halt: \"stopped\""
    end

    test "formats skip result" do
      signal = Signal.new(:test, "data")

      handler =
        Debug.trace_handler("test", fn _, state ->
          {:skip, state}
        end)

      log =
        strip_color(
          capture_log(fn ->
            handler.(signal, %{})
          end)
        )

      assert log =~ "Skip"
    end
  end
end
