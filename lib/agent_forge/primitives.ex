defmodule AgentForge.Primitives do
  @moduledoc """
  Provides basic primitives for building dynamic workflows.
  Includes fundamental building blocks like branching, transformation, and iteration.
  """

  alias AgentForge.{Flow, Signal}

  @doc """
  Creates a branch primitive that executes different handlers based on a condition.

  ## Options

  * `:condition` - A function that takes a signal and state and returns a boolean
  * `:then_flow` - Flow to execute when condition is true
  * `:else_flow` - Flow to execute when condition is false

  ## Examples

      iex> branch = AgentForge.Primitives.branch(
      ...>   fn signal, _ -> signal.data > 10 end,
      ...>   [fn signal, state -> {AgentForge.Signal.emit(:high, signal.data), state} end],
      ...>   [fn signal, state -> {AgentForge.Signal.emit(:low, signal.data), state} end]
      ...> )
      iex> signal = AgentForge.Signal.new(:value, 15)
      iex> {result, _} = branch.(signal, %{})
      iex> match?({:emit, %{type: :high}}, result)
      true
  """
  def branch(condition, then_flow, else_flow) when is_function(condition, 2) do
    fn signal, state ->
      flow_to_use = if condition.(signal, state), do: then_flow, else: else_flow
      process_branch_flow(flow_to_use, signal, state)
    end
  end

  # Helper function to process the selected branch flow
  defp process_branch_flow(flow, signal, state) do
    case Flow.process(flow, signal, state) do
      {:ok, result, new_state} -> {{:emit, result}, new_state}
      {:error, reason} -> {{:emit, Signal.new(:error, reason)}, state}
    end
  end

  @doc """
  Creates a transform primitive that modifies signal data.

  ## Examples

      iex> transform = AgentForge.Primitives.transform(fn data -> String.upcase(data) end)
      iex> signal = AgentForge.Signal.new(:text, "hello")
      iex> {{:emit, result}, _} = transform.(signal, %{})
      iex> result.data
      "HELLO"
  """
  def transform(transform_fn) when is_function(transform_fn, 1) do
    fn signal, state ->
      try do
        new_data = transform_fn.(signal.data)
        {{:emit, %{signal | data: new_data}}, state}
      rescue
        e ->
          error = "Transform error: #{Exception.message(e)}"
          {{:emit, Signal.new(:error, error)}, state}
      end
    end
  end

  @doc """
  Creates a loop primitive that iterates over items in the signal data.
  Accumulates results and maintains state across iterations.

  ## Examples

      iex> handler = fn item, state ->
      ...>   {AgentForge.Signal.emit(:item, item), Map.update(state, :sum, item, &(&1 + item))}
      ...> end
      iex> loop = AgentForge.Primitives.loop(handler)
      iex> signal = AgentForge.Signal.new(:list, [1, 2, 3])
      iex> {result, state} = loop.(signal, %{})
      iex> match?({:emit_many, _}, result) and state.sum == 6
      true
  """
  def loop(item_handler) when is_function(item_handler, 2) do
    fn signal, state ->
      items = signal.data

      if is_list(items) do
        try do
          {results, final_state} =
            Enum.reduce(items, {[], state}, fn item, {results, current_state} ->
              case item_handler.(item, current_state) do
                {{:emit, result}, new_state} -> {[result | results], new_state}
                {{:emit_many, new_results}, new_state} -> {new_results ++ results, new_state}
                {{:halt, result}, new_state} -> throw({:halt, result, new_state})
                {:skip, new_state} -> {results, new_state}
                error -> throw({:error, "Invalid handler result: #{inspect(error)}"})
              end
            end)

          {{:emit_many, Enum.reverse(results)}, final_state}
        catch
          {:halt, result, new_state} -> {{:halt, result}, new_state}
          {:error, reason} -> {{:error, reason}, state}
        end
      else
        {{:emit, Signal.new(:error, "Loop data must be a list")}, state}
      end
    end
  end

  @doc """
  Creates a sequence primitive that executes multiple handlers in order,
  passing the result of each to the next.

  ## Examples

      iex> handlers = [
      ...>   fn signal, state -> {AgentForge.Signal.emit(:step1, signal.data <> "_1"), state} end,
      ...>   fn signal, state -> {AgentForge.Signal.emit(:step2, signal.data <> "_2"), state} end
      ...> ]
      iex> sequence = AgentForge.Primitives.sequence(handlers)
      iex> signal = AgentForge.Signal.new(:start, "data")
      iex> {{:emit, result}, _} = sequence.(signal, %{})
      iex> result.data
      "data_1_2"
  """
  def sequence(handlers) when is_list(handlers) do
    fn signal, state ->
      case Flow.process(handlers, signal, state) do
        {:ok, result, new_state} -> {{:emit, result}, new_state}
        {:error, reason} -> {{:emit, Signal.new(:error, reason)}, state}
      end
    end
  end

  @doc """
  Creates a wait primitive that pauses execution until a condition is met.
  Returns {:wait, reason} while waiting, {:emit, signal} when condition is met.

  ## Options

  * `:condition` - A function that takes a signal and state and returns a boolean
  * `:timeout` - Optional timeout in milliseconds, defaults to 5000
  * `:retry_interval` - Optional retry interval in milliseconds, defaults to 100

  ## Examples

      iex> wait = AgentForge.Primitives.wait(
      ...>   fn _, state -> Map.get(state, :ready, false) end,
      ...>   timeout: 1000
      ...> )
      iex> signal = AgentForge.Signal.new(:check, "waiting")
      iex> state = %{ready: false}
      iex> {{:wait, reason}, _state} = wait.(signal, state)
      iex> is_binary(reason)
      true
  """
  def wait(condition, opts \\ []) when is_function(condition, 2) do
    timeout = Keyword.get(opts, :timeout, 5000)
    retry_interval = Keyword.get(opts, :retry_interval, 100)
    start_time = :os.system_time(:millisecond)

    fn signal, state ->
      current_time = :os.system_time(:millisecond)
      elapsed_time = current_time - start_time

      cond do
        condition.(signal, state) ->
          {{:emit, signal}, state}

        elapsed_time >= timeout ->
          {{:emit, Signal.new(:error, "Wait operation timed out after #{timeout}ms")}, state}

        true ->
          Process.sleep(retry_interval)
          # Keep original message format for backward compatibility
          {{:wait, "Waiting for condition to be met"}, state}
      end
    end
  end

  @doc """
  Creates a notify primitive that sends notifications through configured channels.

  ## Options

  * `:channels` - List of notification channels (e.g. [:console, :slack])
  * `:format` - Optional function to format the notification message
  * `:config` - Optional configuration map for channels

  ## Examples

      iex> notify = AgentForge.Primitives.notify([:console])
      iex> signal = AgentForge.Signal.new(:event, "System alert")
      iex> {{:emit, result}, _} = notify.(signal, %{})
      iex> result.type == :notification
      true
  """
  def notify(channels, opts \\ []) when is_list(channels) do
    format_fn = Keyword.get(opts, :format, &inspect/1)
    config = Keyword.get(opts, :config, %{})

    fn signal, state ->
      message = format_fn.(signal.data)

      # Process each channel
      Enum.each(channels, fn channel_name ->
        send_notification(channel_name, message, config)
      end)

      {{:emit, Signal.new(:notification, message)}, state}
    end
  end

  # Helper function to send a notification to a specific channel
  defp send_notification(channel_name, message, config) do
    case AgentForge.Notification.Registry.get_channel(channel_name) do
      {:ok, channel_module} ->
        # Get channel-specific config
        channel_config = Map.get(config, channel_name, %{})
        # Send notification
        channel_module.send(message, channel_config)

      :error when channel_name == :console ->
        # Built-in console support for backward compatibility
        IO.puts("[Notification] #{message}")

      :error ->
        # Channel not found, log warning
        IO.warn("Notification channel not found: #{inspect(channel_name)}")
    end
  end
end
