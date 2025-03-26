defmodule AgentForge.Plugin do
  @moduledoc """
  Behaviour specification for AgentForge plugins.

  Plugins can extend the framework with additional tools, primitives, and notification channels.
  """

  @doc """
  Called when the plugin is loaded. Use this for initialization.
  """
  @callback init(opts :: keyword()) :: :ok | {:error, term()}

  @doc """
  Called to register tools provided by this plugin.
  """
  @callback register_tools(registry :: module()) :: :ok | {:error, term()}

  @doc """
  Called to register primitives provided by this plugin.
  """
  @callback register_primitives() :: :ok | {:error, term()}

  @doc """
  Called to register notification channels provided by this plugin.
  """
  @callback register_channels() :: :ok | {:error, term()}

  @doc """
  Returns metadata about the plugin.
  """
  @callback metadata() :: map()

  @optional_callbacks [
    register_tools: 1,
    register_primitives: 0,
    register_channels: 0
  ]
end
