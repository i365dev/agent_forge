defmodule AgentForge.Application do
  @moduledoc """
  The main application module for AgentForge.
  Responsible for starting and supervising the system components.
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Store as a supervised GenServer
      {AgentForge.Store, []}
    ]

    opts = [strategy: :one_for_one, name: AgentForge.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
