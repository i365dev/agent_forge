# Asynchronous Workflow Example
#
# This example demonstrates how to use the wait primitive to handle
# asynchronous operations in a workflow.
#
# To run: mix run examples/async_workflow.exs

defmodule AsyncWorkflow do
  alias AgentForge.{Flow, Signal}

  def simulate_async_job(caller) do
    # Simulate a background job
    spawn(fn ->
      # Very short sleep for example
      Process.sleep(100)
      send(caller, {:job_complete, %{result: "Completed"}})
    end)
  end

  def run do
    # Start async job
    start_job = fn _signal, state ->
      simulate_async_job(self())
      {Signal.emit(:job_started, "Starting async job"), state}
    end

    # Wait and process job completion
    wait_process = fn _signal, state ->
      receive do
        {:job_complete, result} ->
          message = "Job completed with result: #{inspect(result.result)}"
          {Signal.emit(:notification, message), state}
      after
        # Longer timeout to ensure we catch the message
        2000 ->
          {Signal.emit(:error, "Job timed out"), state}
      end
    end

    # Compose workflow
    workflow = [
      start_job,
      wait_process
    ]

    # Execute workflow
    signal = Signal.new(:start, %{job_id: "123"})
    state = %{}

    case Flow.process(workflow, signal, state) do
      {:ok, result, final_state} ->
        IO.puts("Workflow completed successfully")
        IO.inspect(result, label: "Final Result")
        IO.inspect(final_state, label: "Final State")

      {:error, reason} ->
        IO.puts("Workflow failed: #{reason}")
    end
  end
end

# Run the example
AsyncWorkflow.run()
