defmodule AgentForge.PluginManager do
  @moduledoc """
  Manages loading and activation of AgentForge plugins.
  """

  use GenServer

  @doc """
  Starts the plugin manager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Loads a plugin module.
  """
  def load_plugin(plugin_module, opts \\ []) do
    GenServer.call(__MODULE__, {:load_plugin, plugin_module, opts})
  end

  @doc """
  Returns a list of loaded plugins with their metadata.
  """
  def list_plugins do
    GenServer.call(__MODULE__, :list_plugins)
  end

  @doc """
  Returns whether a plugin is loaded.
  """
  def plugin_loaded?(plugin_module) do
    GenServer.call(__MODULE__, {:plugin_loaded, plugin_module})
  end

  # Server implementation

  @impl true
  def init(_opts) do
    {:ok, %{plugins: %{}}}
  end

  @impl true
  def handle_call({:load_plugin, plugin_module, opts}, _from, state) do
    # Validate plugin module implements the Plugin behaviour
    if implements_plugin_behaviour?(plugin_module) do
      case plugin_module.init(opts) do
        :ok ->
          # Register plugin components
          register_plugin_components(plugin_module)

          # Store plugin metadata
          metadata = plugin_module.metadata()
          plugins = Map.put(state.plugins, plugin_module, metadata)

          {:reply, :ok, %{state | plugins: plugins}}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, :invalid_plugin}, state}
    end
  end

  @impl true
  def handle_call(:list_plugins, _from, state) do
    {:reply, state.plugins, state}
  end

  @impl true
  def handle_call({:plugin_loaded, plugin_module}, _from, state) do
    {:reply, Map.has_key?(state.plugins, plugin_module), state}
  end

  # Private helpers

  defp implements_plugin_behaviour?(module) do
    behaviours = module.__info__(:attributes)[:behaviour] || []
    Enum.member?(behaviours, AgentForge.Plugin)
  rescue
    # If module doesn't exist or doesn't have __info__ function
    _error -> false
  end

  defp register_plugin_components(plugin_module) do
    # Register tools if the callback exists
    if function_exported?(plugin_module, :register_tools, 1) do
      plugin_module.register_tools(AgentForge.Tools)
    end

    # Register primitives if the callback exists
    if function_exported?(plugin_module, :register_primitives, 0) do
      plugin_module.register_primitives()
    end

    # Register notification channels if the callback exists
    if function_exported?(plugin_module, :register_channels, 0) do
      plugin_module.register_channels()
    end
  end
end
