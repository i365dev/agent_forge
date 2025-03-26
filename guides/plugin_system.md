# AgentForge Plugin System

This guide explains how to use and extend the AgentForge plugin system.

## Overview

The plugin system enables extending AgentForge with additional functionality while maintaining a lightweight core. Plugins can provide new tools, primitives, and notification channels.

## Using Plugins

To use a plugin in your AgentForge application:

1. Add the plugin to your dependencies in `mix.exs`:

```elixir
defp deps do
  [
    {:agent_forge, "~> 0.1.0"},
    {:agent_forge_http, "~> 1.0.0"}  # Example HTTP plugin
  ]
end
```

2. Load the plugin in your application:

```elixir
# In your application startup code
AgentForge.PluginManager.load_plugin(AgentForge.Plugins.HTTP)
```

3. Use the tools provided by the plugin:

```elixir
signal = AgentForge.Signal.new(:request, %{"url" => "https://example.com"})
flow = [AgentForge.Tools.execute("http_get")]
{:ok, result, _} = AgentForge.Flow.process(flow, signal, %{})
```

## Creating Plugins

To create your own plugin:

1. Implement the `AgentForge.Plugin` behaviour:

```elixir
defmodule MyApp.CustomPlugin do
  @behaviour AgentForge.Plugin
  
  @impl true
  def init(_opts) do
    # Initialize your plugin
    :ok
  end
  
  @impl true
  def register_tools(registry) do
    # Register any tools your plugin provides
    registry.register("my_tool", &my_tool_function/1)
    :ok
  end
  
  @impl true
  def metadata do
    %{
      name: "My Custom Plugin",
      description: "Provides custom functionality",
      version: "1.0.0",
      author: "Your Name",
      compatible_versions: ">= 0.1.0"
    }
  end
  
  # Tool implementation
  defp my_tool_function(params) do
    # Process params and return a result
    %{result: "Processed #{inspect(params)}"}
  end
end
```

2. Optionally register primitives or notification channels:

```elixir
# To register primitives
@impl true
def register_primitives do
  # Register your custom primitives
  :ok
end

# To register notification channels
@impl true
def register_channels do
  AgentForge.Notification.Registry.register_channel(MyApp.Notification.Channels.Custom)
  :ok
end
```

## Notification Channels

Plugins can provide new notification channels by implementing the `AgentForge.Notification.Channel` behaviour:

```elixir
defmodule MyApp.Notification.Channels.Custom do
  @behaviour AgentForge.Notification.Channel
  
  @impl true
  def name, do: :custom
  
  @impl true
  def send(message, config) do
    # Send notification through your custom channel
    IO.puts("Custom notification: #{message}, config: #{inspect(config)}")
    :ok
  end
end
```

To use a custom notification channel:

```elixir
notify = AgentForge.Primitives.notify(
  [:console, :custom],
  config: %{custom: %{some_setting: "value"}}
)

flow = [notify]
signal = AgentForge.Signal.new(:event, "Something happened")
AgentForge.Flow.process(flow, signal, %{})
```

## Best Practices

1. **Keep Plugins Focused**: Each plugin should provide a specific, well-defined set of functionality.

2. **Handle Dependencies Gracefully**: Check for required dependencies with `Code.ensure_loaded?/1` and provide meaningful error messages when they're missing.

3. **Document Your Plugin**: Include clear documentation on how to use your plugin and its configuration options.

4. **Version Compatibility**: Specify which versions of AgentForge your plugin is compatible with.

5. **Testing**: Write comprehensive tests for your plugin to ensure it behaves correctly.
