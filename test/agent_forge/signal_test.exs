defmodule AgentForge.SignalTest do
  use ExUnit.Case
  doctest AgentForge.Signal

  alias AgentForge.Signal

  describe "new/3" do
    test "creates a signal with basic attributes" do
      signal = Signal.new(:test, "data")
      assert signal.type == :test
      assert signal.data == "data"
      assert %{
        source: nil,
        timestamp: %DateTime{},
        trace_id: trace_id,
        correlation_id: nil,
        custom: %{}
      } = signal.meta
      assert is_binary(trace_id)
    end

    test "merges custom metadata" do
      signal = Signal.new(:test, "data", %{custom: %{key: "value"}})
      assert signal.meta.custom.key == "value"
    end
  end

  describe "get_meta/2" do
    test "retrieves metadata values" do
      signal = Signal.new(:test, "data", %{custom: %{key: "value"}})
      assert Signal.get_meta(signal, :custom) == %{key: "value"}
      assert Signal.get_meta(signal, :source) == nil
    end
  end

  describe "update_meta/3" do
    test "updates metadata values" do
      signal = Signal.new(:test, "data")
      updated = Signal.update_meta(signal, :source, "test")
      assert updated.meta.source == "test"
    end
  end

  describe "correlate/2" do
    test "copies trace_id from parent to child correlation_id" do
      parent = Signal.new(:parent, "parent data")
      child = Signal.new(:child, "child data")
      correlated = Signal.correlate(child, parent)
      assert correlated.meta.correlation_id == parent.meta.trace_id
    end
  end

  describe "signal results" do
    test "emit/3 creates an emit result" do
      {:emit, signal} = Signal.emit(:test, "data", %{source: "test"})
      assert signal.type == :test
      assert signal.data == "data"
      assert signal.meta.source == "test"
    end

    test "emit_many/1 creates an emit_many result" do
      {:emit_many, signals} = Signal.emit_many([
        {:test1, "data1"},
        {:test2, "data2", %{source: "test"}}
      ])
      assert length(signals) == 2
      [signal1, signal2] = signals
      assert signal1.type == :test1
      assert signal2.type == :test2
      assert signal2.meta.source == "test"
    end

    test "halt/1 creates a halt result" do
      assert Signal.halt("done") == {:halt, "done"}
    end
  end
end
