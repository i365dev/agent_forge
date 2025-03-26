defmodule AgentForge.PluginSystemTest do
  use ExUnit.Case
  alias AgentForge.{Plugin, PluginManager, Signal}

  # Define a mock plugin for testing
  defmodule MockPlugin do
    @behaviour Plugin

    @impl true
    def init(_opts) do
      :ok
    end

    @impl true
    def register_tools(registry) do
      registry.register("mock_tool", fn params ->
        %{result: "Mock tool processed: #{inspect(params)}"}
      end)

      :ok
    end

    @impl true
    def metadata do
      %{
        name: "Mock Plugin",
        description: "A mock plugin for testing",
        version: "1.0.0",
        author: "Test"
      }
    end
  end

  # Define a mock notification channel
  defmodule MockChannel do
    @behaviour AgentForge.Notification.Channel

    @impl true
    def name, do: :mock

    @impl true
    def send(message, _config) do
      Agent.update(__MODULE__, fn messages -> [message | messages] end)
      :ok
    end

    def start_link do
      Agent.start_link(fn -> [] end, name: __MODULE__)
    end

    def get_messages do
      Agent.get(__MODULE__, & &1)
    end

    def clear do
      Agent.update(__MODULE__, fn _ -> [] end)
    end
  end

  setup do
    # Start mock channel agent
    MockChannel.start_link()
    :ok
  end

  describe "plugin management" do
    test "can load a plugin" do
      assert :ok = PluginManager.load_plugin(MockPlugin)
      assert PluginManager.plugin_loaded?(MockPlugin)
    end

    test "can list loaded plugins" do
      PluginManager.load_plugin(MockPlugin)
      plugins = PluginManager.list_plugins()

      assert Map.has_key?(plugins, MockPlugin)
      plugin_data = Map.get(plugins, MockPlugin)
      assert plugin_data.name == "Mock Plugin"
      assert plugin_data.version == "1.0.0"
    end
  end

  describe "plugin tools" do
    test "can use tools from a plugin" do
      PluginManager.load_plugin(MockPlugin)
      {:ok, tool_fn} = AgentForge.Tools.get("mock_tool")

      result = tool_fn.(%{test: "data"})
      assert is_map(result)
      assert result.result =~ "Mock tool processed"
    end
  end

  describe "notification channels" do
    test "can register and use a notification channel" do
      # Register the mock channel
      AgentForge.Notification.Registry.register_channel(MockChannel)

      # Create a notification using the mock channel
      notify = AgentForge.Primitives.notify([:mock])
      signal = Signal.new(:event, "Test notification")

      # Process the notification
      {{:emit, _result}, _state} = notify.(signal, %{})

      # Verify the notification was sent
      messages = MockChannel.get_messages()
      assert length(messages) == 1
      assert List.first(messages) == "\"Test notification\""
    end
  end
end
