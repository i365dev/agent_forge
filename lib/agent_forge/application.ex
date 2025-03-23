defmodule AgentForge.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Registry.AgentForge},
      {AgentForge.Store, []},
      {AgentForge.Tools, name: AgentForge.Tools}
    ]

    opts = [strategy: :one_for_one, name: AgentForge.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
