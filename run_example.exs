# Helper script to run examples with proper module loading
example_name = System.argv() |> List.first()

unless example_name do
  IO.puts "Usage: elixir run_example.exs [example_name]"
  IO.puts "Available examples:"
  Path.wildcard("examples/*.exs")
  |> Enum.each(fn path ->
    IO.puts "  #{Path.basename(path, ".exs")}"
  end)
  System.halt(1)
end

example_path = "examples/#{example_name}.exs"

unless File.exists?(example_path) do
  IO.puts "Example #{example_name} not found"
  System.halt(1)
end

# Load required modules in correct order
Code.require_file("lib/agent_forge/signal.ex")
Code.require_file("lib/agent_forge/store.ex")
Code.require_file("lib/agent_forge/flow.ex")
Code.require_file("lib/agent_forge/runtime.ex")
Code.require_file("lib/agent_forge/primitives.ex")
Code.require_file("lib/agent_forge.ex")

# Ensure the application is loaded with all dependencies
Application.ensure_all_started(:agent_forge)

# Load and run the example
Code.eval_file(example_path)
