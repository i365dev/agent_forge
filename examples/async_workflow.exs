# Asynchronous Workflow Example
#
# This example demonstrates how to use the wait primitive to handle
# asynchronous operations in a workflow.
#
# To run: elixir examples/async_workflow.exs

Code.require_file("../lib/agent_forge.ex")
Code.require_file("../lib/agent_forge/signal.ex")
Code.require_file("../lib/agent_forge/flow.ex")
Code.require_file("../lib/agent_forge/primitives.ex")

defmodule AsyncWorkflow do
  alias AgentForge.{Flow, Signal, Primitives}

  def simulate_async_job do
    # Simulate a background job
    spawn(fn ->
      Process.sleep(2000)  # Simulate work
      send(self(), {:job_complete, %{result: "Completed"}})
    end)
  end

  def run do
    # Start async job
    start_job = fn signal, state ->
      simulate_async_job()
      {Signal.emit(:job_started, signal.data), state}
    end

    # Wait for job completion
    wait_for_completion = Primitives.wait(
      fn _, state ->
        receive do
          {:job_complete, result} ->
            {true, Map.put(state, :result, result)}
        after
          0 -> false
        end
      end,
      timeout: 5000,
      retry_interval: 100
    )

    # Notify on completion
    notify_completion = Primitives.notify(
      [:console],
      format: fn data -> "Job completed: #{inspect(data)}" end
    )

    # Compose workflow
    workflow = [
      start_job,
      wait_for_completion,
      fn signal, state ->
        result = Map.get(state, :result)
        {Signal.emit(:complete, result), state}
      end,
      notify_completion
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
