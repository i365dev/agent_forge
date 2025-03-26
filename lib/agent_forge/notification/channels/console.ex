defmodule AgentForge.Notification.Channels.Console do
  @moduledoc """
  Console notification channel for AgentForge.
  """

  @behaviour AgentForge.Notification.Channel

  @impl true
  def name, do: :console

  @impl true
  def send(message, config) do
    prefix = Map.get(config, :prefix, "[Notification]")
    IO.puts("#{prefix} #{message}")
    :ok
  end
end
