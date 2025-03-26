defmodule AgentForge.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Registry.AgentForge},
      {AgentForge.Store, []},
      {AgentForge.Tools, name: AgentForge.Tools},
      # Add plugin manager
      {AgentForge.PluginManager, []},
      # Add notification registry
      {AgentForge.Notification.Registry, []}
    ]

    opts = [strategy: :one_for_one, name: AgentForge.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
