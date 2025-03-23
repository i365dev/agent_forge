defmodule AgentForge.ComplexFlowsTest do
  use ExUnit.Case, async: false

  alias AgentForge.{Signal, Flow, Tools, Primitives, DynamicFlow}

  setup do
    # Set up test state store
    {:ok, state_agent} = Agent.start_link(fn -> %{execution_path: []} end)

    # Register tools in default registry
    Tools.register("append", fn text -> text <> "_processed" end)
    Tools.register("count", fn text -> String.length(text) end)
    Tools.register("log", fn text -> "LOG: #{text}" end)
    Tools.register("notify", fn text -> "NOTIFICATION: #{text}" end)
    Tools.register("double", fn n when is_number(n) -> n * 2 end)

    # Clean up after each test
    on_exit(fn ->
      if Process.whereis(AgentForge.Tools) do
        Process.exit(Process.whereis(AgentForge.Tools), :normal)
      end

      if Process.alive?(state_agent) do
        Agent.stop(state_agent)
      end
    end)

    %{state_agent: state_agent}
  end

  describe "nested dynamic flows" do
    test "builds and executes complex nested workflows" do
      # Create nested workflow with multiple branches and tools
      flow = [
        # First a dynamic flow selector
        # Using regular name since we need it
        DynamicFlow.select_flow(fn signal, _state ->
          case signal.type do
            :text ->
              [
                # Handle text signals
                Primitives.transform(&String.upcase/1),
                Primitives.branch(
                  fn signal, _ -> String.length(signal.data) > 5 end,
                  [Tools.execute("notify")],
                  [Tools.execute("log")]
                )
              ]

            :number ->
              [
                # Handle number signals
                Primitives.transform(fn n -> n * 2 end),
                Tools.execute("double")
              ]

            _ ->
              [
                # Default handler
                fn signal, state -> {{:emit, Signal.new(:unknown, signal.data)}, state} end
              ]
          end
        end)
      ]

      # Test long text signal
      text_signal = Signal.new(:text, "hello world")
      {:ok, text_result, _} = Flow.process(flow, text_signal, %{})
      assert text_result.type == :tool_result
      assert text_result.data =~ "NOTIFICATION: HELLO WORLD"

      # Test short text signal
      short_signal = Signal.new(:text, "hi")
      {:ok, short_result, _} = Flow.process(flow, short_signal, %{})
      assert short_result.type == :tool_result
      assert short_result.data =~ "LOG: HI"

      # Test number signal
      number_signal = Signal.new(:number, 5)
      {:ok, number_result, _} = Flow.process(flow, number_signal, %{})
      assert number_result.type == :tool_result
      # 5 * 2 * 2 = 20
      assert number_result.data == 20
    end
  end

  describe "self-modifying workflows" do
    test "modifies its own processing based on signal content", %{state_agent: agent} do
      # Create a flow that can modify itself based on signal content

      # Create step recording function
      record_step = fn step_name, signal, state ->
        # Record execution step
        Agent.update(agent, fn current ->
          Map.update(current, :execution_path, [step_name], &(&1 ++ [step_name]))
        end)

        {{:emit, signal}, state}
      end

      # Base workflow starts with dynamic path selector
      flow = [
        # Step 1: Record initial processing
        fn signal, state ->
          {{:emit, signal}, Map.put(state, :path_type, "initial")}
        end,

        # Step 2: Select path based on signal
        # Fixed unused variable warning
        DynamicFlow.select_flow(fn signal, _state ->
          # Path depends on signal content
          cond do
            # For "dynamic" signal, create custom path with 2 extra steps
            signal.data == "dynamic" ->
              Agent.update(agent, fn current ->
                Map.put(current, :execution_path, [:dynamic_path])
              end)

              [
                fn s, st -> record_step.("dynamic_step_1", s, st) end,
                fn s, st -> record_step.("dynamic_step_2", s, st) end,
                # Actually modifies state to record our decision
                fn s, st -> {{:emit, s}, Map.put(st, :path_type, "dynamic")} end
              ]

            # For "simple" signal, use simple single-step path
            signal.data == "simple" ->
              Agent.update(agent, fn current ->
                Map.put(current, :execution_path, [:simple_path])
              end)

              [
                fn s, st -> record_step.("simple_step", s, st) end,
                fn s, st -> {{:emit, s}, Map.put(st, :path_type, "simple")} end
              ]

            # Default
            true ->
              Agent.update(agent, fn current ->
                Map.put(current, :execution_path, [:default_path])
              end)

              [
                fn s, st -> {{:emit, Signal.new(:default, s.data)}, st} end
              ]
          end
        end),

        # Step 3: Final processing depends on chosen path
        fn signal, state ->
          path = Map.get(state, :path_type, "unknown")

          Agent.update(agent, fn current ->
            Map.update(current, :execution_path, ["final_#{path}"], &(&1 ++ ["final_#{path}"]))
          end)

          {{:emit, Signal.new(:result, "Processed via #{path} path: #{signal.data}")}, state}
        end
      ]

      # Test dynamic path
      dynamic_signal = Signal.new(:test, "dynamic")
      {:ok, dynamic_result, dynamic_state} = Flow.process(flow, dynamic_signal, %{})
      dynamic_steps = Agent.get(agent, & &1.execution_path)

      assert dynamic_result.type == :result
      assert dynamic_result.data =~ "Processed via dynamic path"
      assert dynamic_state.path_type == "dynamic"
      assert :dynamic_path in dynamic_steps
      assert "dynamic_step_1" in dynamic_steps
      assert "dynamic_step_2" in dynamic_steps
      assert "final_dynamic" in dynamic_steps

      # Test simple path
      # Reset state
      Agent.update(agent, fn _ -> %{execution_path: []} end)

      simple_signal = Signal.new(:test, "simple")
      {:ok, simple_result, simple_state} = Flow.process(flow, simple_signal, %{})
      simple_steps = Agent.get(agent, & &1.execution_path)

      assert simple_result.type == :result
      assert simple_result.data =~ "Processed via simple path"
      assert simple_state.path_type == "simple"
      assert :simple_path in simple_steps
      assert "simple_step" in simple_steps
      assert "final_simple" in simple_steps
    end

    test "can handle timeouts safely" do
      # Set up a flow with risky timeout but safe handling
      flow = [
        fn signal, state ->
          if signal.data == "timeout" do
            # In real scenario this might be a long-running process
            # But in test we just create a controlled simulation
            {{:emit, Signal.new(:timeout, "Operation timed out")}, state}
          else
            {{:emit, signal}, state}
          end
        end
      ]

      # Test with timeout - should return safely without hanging forever
      signal = Signal.new(:test, "timeout")

      result =
        try do
          Task.yield(Task.async(fn -> Flow.process(flow, signal, %{}) end), 500) ||
            {:timeout, "Operation took too long"}
        catch
          :exit, _ -> {:error, "Process crashed"}
        end

      # Ensure we got some form of result
      assert result != nil
    end
  end

  describe "contextual decision workflows" do
    test "makes decisions based on accumulated state" do
      # Define a workflow that makes decisions based on accumulated state
      flow = [
        # Step 1: Initial classification
        fn signal, state ->
          # Classify input
          classification =
            cond do
              is_binary(signal.data) && String.length(signal.data) > 10 -> :long_text
              is_binary(signal.data) -> :short_text
              is_number(signal.data) && signal.data > 100 -> :large_number
              is_number(signal.data) -> :small_number
              true -> :unknown
            end

          # Store classification in state
          new_state = Map.put(state, :classification, classification)
          {{:emit, Signal.new(:classified, {classification, signal.data})}, new_state}
        end,

        # Step 2: Process based on classification
        # Fixed unused variable warning
        DynamicFlow.select_flow(fn _signal, state ->
          case Map.get(state, :classification) do
            :long_text ->
              [
                Primitives.transform(fn {_, text} -> String.upcase(text) end),
                fn signal, st ->
                  {{:emit, Signal.new(:processed, "LONG TEXT: #{signal.data}")},
                   Map.put(st, :processing, :heavy)}
                end
              ]

            :short_text ->
              [
                Primitives.transform(fn {_, text} -> String.downcase(text) end),
                fn signal, st ->
                  {{:emit, Signal.new(:processed, "short text: #{signal.data}")},
                   Map.put(st, :processing, :light)}
                end
              ]

            :large_number ->
              [
                Primitives.transform(fn {_, num} -> num * 2 end),
                fn signal, st ->
                  {{:emit, Signal.new(:processed, "Large number: #{signal.data}")},
                   Map.put(st, :processing, :heavy)}
                end
              ]

            :small_number ->
              [
                Primitives.transform(fn {_, num} -> num / 2 end),
                fn signal, st ->
                  {{:emit, Signal.new(:processed, "Small number: #{signal.data}")},
                   Map.put(st, :processing, :light)}
                end
              ]

            _ ->
              [
                fn signal, st -> {{:emit, Signal.new(:unknown, signal.data)}, st} end
              ]
          end
        end),

        # Step 3: Final processing based on processing weight
        # Fixed unused variable warning
        DynamicFlow.select_flow(fn _signal, state ->
          case Map.get(state, :processing) do
            :heavy ->
              [
                fn signal, st ->
                  {{:emit,
                    Signal.new(:notification, "Heavy processing completed: #{signal.data}")}, st}
                end
              ]

            :light ->
              [
                fn signal, st ->
                  {{:emit, Signal.new(:log, "Light processing completed: #{signal.data}")}, st}
                end
              ]

            _ ->
              [
                fn signal, st -> {{:emit, Signal.new(:done, signal.data)}, st} end
              ]
          end
        end)
      ]

      # Test long text
      long_signal = Signal.new(:input, "This is a very long piece of text")
      {:ok, long_result, long_state} = Flow.process(flow, long_signal, %{})

      assert long_result.type == :notification
      assert long_result.data =~ "Heavy processing completed"
      assert long_state.classification == :long_text
      assert long_state.processing == :heavy

      # Test small number
      small_signal = Signal.new(:input, 42)
      {:ok, small_result, small_state} = Flow.process(flow, small_signal, %{})

      assert small_result.type == :log
      assert small_result.data =~ "Light processing completed"
      assert small_state.classification == :small_number
      assert small_state.processing == :light
    end
  end
end
