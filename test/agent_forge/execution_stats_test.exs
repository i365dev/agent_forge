defmodule AgentForge.ExecutionStatsTest do
  use ExUnit.Case
  doctest AgentForge.ExecutionStats

  alias AgentForge.ExecutionStats
  alias AgentForge.Signal

  describe "new/0" do
    test "creates new stats with initial values" do
      stats = ExecutionStats.new()
      assert stats.steps == 0
      assert stats.signal_types == %{}
      assert stats.handler_calls == %{}
      assert stats.max_state_size == 0
      assert stats.complete == false
      assert stats.elapsed_ms == nil
      assert stats.result == nil
      assert is_integer(stats.start_time)
    end
  end

  describe "record_step/4" do
    test "increments steps and tracks signal types" do
      stats = ExecutionStats.new()
      signal = Signal.new(:test_signal, "data")
      state = %{key: "value"}

      updated_stats = ExecutionStats.record_step(stats, :test_handler, signal, state)

      assert updated_stats.steps == 1
      assert updated_stats.signal_types == %{test_signal: 1}
      assert updated_stats.handler_calls == %{test_handler: 1}
      assert updated_stats.max_state_size == 1
    end

    test "tracks multiple signal types and handlers" do
      stats = ExecutionStats.new()
      signal1 = Signal.new(:type_a, "data1")
      signal2 = Signal.new(:type_b, "data2")
      signal3 = Signal.new(:type_a, "data3")
      state = %{key1: "value1", key2: "value2"}

      stats = ExecutionStats.record_step(stats, :handler1, signal1, %{})
      stats = ExecutionStats.record_step(stats, :handler2, signal2, state)
      stats = ExecutionStats.record_step(stats, :handler1, signal3, state)

      assert stats.steps == 3
      assert stats.signal_types == %{type_a: 2, type_b: 1}
      assert stats.handler_calls == %{handler1: 2, handler2: 1}
      assert stats.max_state_size == 2
    end

    test "handles non-map state" do
      stats = ExecutionStats.new()
      signal = Signal.new(:test, "data")

      updated_stats = ExecutionStats.record_step(stats, :handler, signal, nil)

      assert updated_stats.steps == 1
      assert updated_stats.max_state_size == 0
    end
  end

  describe "finalize/2" do
    test "completes stats with result and elapsed time" do
      stats = ExecutionStats.new()
      result = {:ok, "success"}

      # Ensure some time passes
      :timer.sleep(1)
      stats = ExecutionStats.finalize(stats, result)

      assert stats.complete == true
      assert stats.result == result
      assert stats.elapsed_ms > 0
    end
  end

  describe "format_report/1" do
    test "generates readable report" do
      stats = ExecutionStats.new()
      signal = Signal.new(:test_signal, "data")

      stats =
        stats
        |> ExecutionStats.record_step(:handler, signal, %{a: 1})
        |> ExecutionStats.finalize({:ok, "done"})

      report = ExecutionStats.format_report(stats)

      assert is_binary(report)
      assert report =~ "Total Steps: 1"
      assert report =~ "Signal Types: test_signal: 1"
      assert report =~ "Handler Calls: handler: 1"
      assert report =~ "Max State Size: 1"
      assert report =~ ~s(Result: {:ok, "done"})
    end
  end
end
