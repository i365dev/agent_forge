defmodule AgentForge.Notification.Channel do
  @moduledoc """
  Behaviour for notification channels in AgentForge.
  """

  @callback name() :: atom()
  @callback send(message :: String.t(), config :: map()) :: :ok | {:error, term()}
end
