defmodule AgentForge.FlowStatsTest do
  use ExUnit.Case

  alias AgentForge.{ExecutionStats, Flow, Signal}

  setup do
    # Clear any previous execution stats before each test
    Process.put(:"$agent_forge_last_execution_stats", nil)
    :ok
  end

  describe "flow execution statistics" do
    test "collects basic execution stats" do
      signal = Signal.new(:test, "data")
      handler = fn sig, state -> {{:emit, sig}, state} end

      assert {:ok, ^signal, %{}} = Flow.process([handler], signal, %{})

      stats = Flow.get_last_execution_stats()
      assert %ExecutionStats{} = stats
      assert stats.steps == 1
      assert stats.signal_types == %{test: 1}
      assert stats.complete == true
      assert is_integer(stats.elapsed_ms) and stats.elapsed_ms >= 0
      assert stats.result == {:ok, signal}
    end

    test "tracks multiple handlers" do
      signal = Signal.new(:initial, "data")

      handlers = [
        fn sig, state -> {{:emit, Signal.new(:step1, sig.data)}, state} end,
        fn sig, state -> {{:emit, Signal.new(:step2, sig.data)}, state} end,
        fn sig, state -> {{:emit, Signal.new(:final, sig.data)}, state} end
      ]

      Flow.process(handlers, signal, %{})
      stats = Flow.get_last_execution_stats()

      assert stats.steps == 3
      assert stats.signal_types == %{initial: 1, step1: 1, step2: 1}
      # Handler calls are tracked by function reference, so just verify the count
      assert map_size(stats.handler_calls) == 3
      assert Enum.all?(Map.values(stats.handler_calls), &(&1 == 1))
    end

    test "handles early termination with skip" do
      signal = Signal.new(:test, "data")

      handlers = [
        fn _sig, state -> {:skip, state} end,
        fn _sig, state -> {{:emit, Signal.new(:never_reached, "data")}, state} end
      ]

      Flow.process(handlers, signal, %{})
      stats = Flow.get_last_execution_stats()

      assert stats.steps == 1
      assert stats.signal_types == %{test: 1}
      assert stats.result == {:ok, nil}
    end

    test "handles errors in flow" do
      signal = Signal.new(:test, "data")

      handlers = [
        fn _sig, state -> {{:error, "test error"}, state} end
      ]

      assert {:error, "test error"} = Flow.process(handlers, signal, %{})
      stats = Flow.get_last_execution_stats()

      assert stats.steps == 1
      assert stats.signal_types == %{test: 1}
      assert stats.result == {:error, "test error"}
    end

    test "tracks state size changes" do
      signal = Signal.new(:test, "data")

      handlers = [
        fn sig, state -> {{:emit, sig}, Map.put(state, :a, 1)} end,
        fn sig, state -> {{:emit, sig}, Map.put(state, :b, 2)} end,
        fn sig, state -> {{:emit, sig}, Map.delete(state, :a)} end
      ]

      Flow.process(handlers, signal, %{})
      stats = Flow.get_last_execution_stats()

      assert stats.max_state_size == 2
    end

    test "handles emit_many signals" do
      signal = Signal.new(:test, "data")

      handlers = [
        fn _sig, state ->
          signals = [
            Signal.new(:first, "data1"),
            Signal.new(:second, "data2")
          ]

          {{:emit_many, signals}, state}
        end
      ]

      Flow.process(handlers, signal, %{})
      stats = Flow.get_last_execution_stats()

      assert stats.steps == 1
      assert stats.signal_types == %{test: 1}
      assert stats.complete == true
    end
  end
end
