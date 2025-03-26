defmodule AgentForge.Notification.Registry do
  @moduledoc """
  Registry for notification channels.
  """

  use GenServer

  # Client API

  @doc """
  Starts the notification registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a notification channel.
  """
  def register_channel(channel_module) do
    GenServer.call(__MODULE__, {:register, channel_module})
  end

  @doc """
  Gets a channel by name.
  """
  def get_channel(name) do
    GenServer.call(__MODULE__, {:get, name})
  end

  @doc """
  Lists all registered channels.
  """
  def list_channels do
    GenServer.call(__MODULE__, :list)
  end

  # Server implementation

  @impl true
  def init(_) do
    {:ok, %{channels: %{}}}
  end

  @impl true
  def handle_call({:register, channel_module}, _from, state) do
    name = channel_module.name()
    channels = Map.put(state.channels, name, channel_module)
    {:reply, :ok, %{state | channels: channels}}
  end

  @impl true
  def handle_call({:get, name}, _from, state) do
    result = Map.fetch(state.channels, name)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, Map.keys(state.channels), state}
  end
end
