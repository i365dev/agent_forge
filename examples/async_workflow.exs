# Asynchronous Workflow Example
#
# This example demonstrates how to use the wait primitive to handle
# asynchronous operations in a workflow.
#
# To run: elixir examples/async_workflow.exs

Code.require_file("lib/agent_forge.ex")
Code.require_file("lib/agent_forge/signal.ex")
Code.require_file("lib/agent_forge/flow.ex")
Code.require_file("lib/agent_forge/primitives.ex")

defmodule AsyncWorkflow do
  alias AgentForge.{Flow, Signal}

  def simulate_async_job(caller) do
    # Simulate a background job
    spawn(fn ->
      Process.sleep(100)  # Very short sleep for example
      send(caller, {:job_complete, %{result: "Completed"}})
    end)
  end

  def run do
    # Start async job
    start_job = fn signal, state ->
      simulate_async_job(self())
      {Signal.emit(:job_started, signal.data), state}
    end

    # Wait and process job completion
    wait_process = fn signal, state ->
      receive do
        {:job_complete, result} ->
          message = "Job completed with result: #{inspect(result.result)}"
          {Signal.emit(:notification, message), state}
      after
        2000 -> # Longer timeout to ensure we catch the message
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
