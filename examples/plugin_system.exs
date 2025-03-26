defmodule WeatherPlugin do
  @moduledoc """
  Example plugin that provides weather forecast functionality.
  """
  @behaviour AgentForge.Plugin

  @impl true
  def init(_opts) do
    # In a real plugin, we might initialize connections or load configs
    # No IO.puts here, we'll print it in the main program flow
    :ok
  end

  @impl true
  def register_tools(registry) do
    registry.register("get_forecast", &forecast/1)
    :ok
  end

  @impl true
  def register_primitives do
    # This plugin doesn't add any primitives
    :ok
  end

  @impl true
  def register_channels do
    AgentForge.Notification.Registry.register_channel(WeatherNotificationChannel)
    :ok
  end

  @impl true
  def metadata do
    %{
      name: "Weather Plugin",
      version: "1.0.0",
      description: "Provides weather forecast functionality",
      author: "AgentForge Team",
      compatible_versions: ">= 0.1.0"
    }
  end

  # Tool implementation
  defp forecast(params) do
    location = Map.get(params, "location", "Unknown")
    # In a real plugin, this would make an API call to a weather service
    # For this example, we just return mock data
    %{
      location: location,
      temperature: 22,
      conditions: "Sunny",
      forecast: [
        %{day: "Today", high: 24, low: 18, conditions: "Sunny"},
        %{day: "Tomorrow", high: 22, low: 17, conditions: "Partly Cloudy"}
      ]
    }
  end
end

defmodule WeatherNotificationChannel do
  @moduledoc """
  Example notification channel for weather alerts.
  """
  @behaviour AgentForge.Notification.Channel

  @impl true
  def name, do: :weather_alert

  @impl true
  def send(message, config) do
    priority = Map.get(config, :priority, "normal")
    # Remove quotes from message to match expected test format
    clean_message = message |> String.replace("\"", "")
    IO.puts("[Weather Alert - #{priority}] #{clean_message}")
    :ok
  end
end

# Start necessary processes
_registry_pid = case AgentForge.Notification.Registry.start_link([]) do
  {:ok, pid} -> pid
  {:error, {:already_started, pid}} -> pid
end

_plugin_manager_pid = case AgentForge.PluginManager.start_link([]) do
  {:ok, pid} -> pid
  {:error, {:already_started, pid}} -> pid
end

_tools_pid = case AgentForge.Tools.start_link([]) do
  {:ok, pid} -> pid
  {:error, {:already_started, pid}} -> pid
end

# Load the weather plugin
IO.puts("Initializing Weather Plugin")
:ok = AgentForge.PluginManager.load_plugin(WeatherPlugin)

# Define a simple flow that uses the weather plugin
process_weather = fn signal, state ->
  location = signal.data
  
  # Use the plugin tool to get weather forecast
  {:ok, forecast_tool} = AgentForge.Tools.get("get_forecast")
  forecast = forecast_tool.(%{"location" => location})
  
  # Emit a notification for extreme temperatures
  if forecast.temperature > 30 do
    notify = AgentForge.Primitives.notify(
      [:weather_alert], 
      config: %{weather_alert: %{priority: "high"}}
    )
    
    alert_signal = AgentForge.Signal.new(:alert, "Extreme heat warning for #{location}")
    notify.(alert_signal, state)
  end
  
  # Return the forecast data
  {{:emit, forecast}, state}
end

# Create and execute a simple flow with a list of handlers
flow = [process_weather]

# Run the flow with different locations
locations = ["San Francisco", "Tokyo", "Sahara Desert"]

Enum.each(locations, fn location ->
  signal = AgentForge.Signal.new(:location, location)
  IO.puts("\nChecking weather for: #{location}")
  {:ok, result, _state} = AgentForge.Flow.process(flow, signal, %{})
  IO.puts("Current conditions: #{result.temperature}°C, #{result.conditions}")
  
  # For demo purposes, simulate a high temperature for Sahara Desert
  if location == "Sahara Desert" do
    hot_signal = AgentForge.Signal.new(:location, location)
    # Monkey patch the forecast tool temporarily to return extreme temperature
    {:ok, old_fn} = AgentForge.Tools.get("get_forecast")
    
    AgentForge.Tools.register("get_forecast", fn params ->
      result = old_fn.(params)
      Map.put(result, :temperature, 45)
    end)
    
    {:ok, _result, _state} = AgentForge.Flow.process(flow, hot_signal, %{})
    
    # Restore original function
    AgentForge.Tools.register("get_forecast", old_fn)
  end
end)

# List all loaded plugins and their metadata
plugins = AgentForge.PluginManager.list_plugins()
IO.puts("\nLoaded Plugins:")
Enum.each(plugins, fn {_module, metadata} ->
  IO.puts("- #{metadata.name} v#{metadata.version}: #{metadata.description}")
end)
