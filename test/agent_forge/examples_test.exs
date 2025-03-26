defmodule AgentForge.ExamplesTest do
  use ExUnit.Case
  doctest AgentForge

  def capture_io(fun) do
    ExUnit.CaptureIO.capture_io(fun)
  end

  describe "data_processing.exs" do
    test "correctly processes orders with tax calculations" do
      output = capture_io(fn -> Code.eval_file("examples/data_processing.exs") end)

      # Verify standard order processing
      assert output =~ ~r/Standard order processed:.*id: 1, total: 550.0/
      # Verify large order notification
      assert output =~ "[Notification] Large order received: #2 (Total: $1320.0)"
      # Verify another standard order
      assert output =~ ~r/Standard order processed:.*id: 3, total: 880.0/
    end
  end

  describe "config_workflow.exs" do
    test "handles validation and age-based routing" do
      output = capture_io(fn -> Code.eval_file("examples/config_workflow.exs") end)

      # Verify adult processing
      assert output =~ "Processing adult user: John Doe"
      # Verify minor processing
      assert output =~ "Cannot process minor: Jane Smith"
      # Verify validation errors
      assert output =~ "name is required"
      assert output =~ "age must be at least 0"
    end
  end

  describe "async_workflow.exs" do
    test "handles async operations correctly" do
      output = capture_io(fn -> Code.eval_file("examples/async_workflow.exs") end)

      # Verify workflow completion and job result
      assert output =~ "Workflow completed successfully"
      assert output =~ ~r/data: "Job completed with result: \\"Completed\\""/
    end
  end

  describe "limited_workflow.exs" do
    test "demonstrates execution limits and statistics" do
      output = capture_io(fn -> Code.eval_file("examples/limited_workflow.exs") end)

      # Verify basic timeout example
      assert output =~ "--- Basic Example with Timeout ---"
      assert output =~ ~r/Processing signal: task -> "Sample data"/
      assert output =~ ~r/Result: processed -> "Sample data"/

      # Verify statistics collection
      assert output =~ "--- Example with Statistics Collection ---"
      assert output =~ "Validating data..."
      assert output =~ "Transforming data..."
      assert output =~ "Finalizing..."
      assert output =~ ~r/Result: completed -> "Test data \(transformed\)"/
      assert output =~ "Execution Statistics:"

      # Verify timeout error handling
      assert output =~ "--- Example with Timeout Error ---"
      assert output =~ "Starting long process..."
      assert output =~ "Error handled gracefully: "
      assert output =~ "Timeout Statistics:"
      assert output =~ "- Completed: true"
    end
  end

  describe "plugin_system.exs" do
    test "demonstrates plugin system functionality" do
      output = capture_io(fn -> Code.eval_file("examples/plugin_system.exs") end)

      # Verify plugin initialization
      assert output =~ "Initializing Weather Plugin"

      # Verify plugin tool usage
      assert output =~ "Checking weather for: San Francisco"
      assert output =~ "Current conditions:"

      # Verify notification channel functionality
      assert output =~ "[Weather Alert - high] Extreme heat warning for Sahara Desert"

      # Verify plugin metadata listing
      assert output =~ "Loaded Plugins:"
      assert output =~ "Weather Plugin v1.0.0: Provides weather forecast functionality"
    end
  end
end
