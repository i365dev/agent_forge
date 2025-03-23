defmodule AgentForge.Signal do
  @moduledoc """
  Handles creation and manipulation of signals in the AgentForge system.
  Signals are the fundamental unit of communication.
  """

  @type t :: %{
    type: atom(),
    data: term(),
    meta: %{
      source: String.t() | nil,
      timestamp: DateTime.t() | nil,
      trace_id: String.t() | nil,
      correlation_id: String.t() | nil,
      custom: map()
    }
  }

  @type signal_result ::
    {:emit, t()} |
    {:emit_many, [t()]} |
    {:halt, term()} |
    :skip

  @doc """
  Creates a new signal with the given type and data.

  ## Examples

      iex> signal = AgentForge.Signal.new(:user_message, "Hello")
      iex> signal.type == :user_message and signal.data == "Hello"
      true
  """
  def new(type, data, meta \\ %{}) when is_atom(type) do
    base_meta = %{
      source: nil,
      timestamp: DateTime.utc_now(),
      trace_id: generate_trace_id(),
      correlation_id: nil,
      custom: %{}
    }

    %{
      type: type,
      data: data,
      meta: Map.merge(base_meta, meta)
    }
  end

  @doc """
  Gets a metadata value from a signal.

  ## Examples

      iex> signal = AgentForge.Signal.new(:test, "data", %{custom: %{key: "value"}})
      iex> AgentForge.Signal.get_meta(signal, :custom)
      %{key: "value"}
  """
  def get_meta(%{meta: meta}, key) when is_atom(key) do
    Map.get(meta, key)
  end

  @doc """
  Updates metadata in a signal.

  ## Examples

      iex> signal = AgentForge.Signal.new(:test, "data")
      iex> updated = AgentForge.Signal.update_meta(signal, :custom, %{key: "value"})
      iex> get_in(updated.meta, [:custom, :key])
      "value"
  """
  def update_meta(%{meta: meta} = signal, key, value) when is_atom(key) do
    %{signal | meta: Map.put(meta, key, value)}
  end

  @doc """
  Creates a new signal correlated with a parent signal.
  Copies the parent's trace_id into the new signal's correlation_id.

  ## Examples

      iex> parent = AgentForge.Signal.new(:parent, "data")
      iex> child = AgentForge.Signal.correlate(AgentForge.Signal.new(:child, "response"), parent)
      iex> child.meta.correlation_id == parent.meta.trace_id
      true
  """
  def correlate(%{meta: child_meta} = child, %{meta: %{trace_id: trace_id}}) do
    %{child | meta: Map.put(child_meta, :correlation_id, trace_id)}
  end

  @doc """
  Creates an emit result with a new signal.

  ## Examples

      iex> {:emit, signal} = AgentForge.Signal.emit(:test, "data")
      iex> signal.type == :test and signal.data == "data"
      true
  """
  def emit(type, data, meta \\ %{}) do
    {:emit, new(type, data, meta)}
  end

  @doc """
  Creates an emit_many result with multiple signals.

  ## Examples

      iex> {:emit_many, signals} = AgentForge.Signal.emit_many([
      ...>   {:test1, "data1"},
      ...>   {:test2, "data2"}
      ...> ])
      iex> length(signals) == 2
      true
  """
  def emit_many(signals) when is_list(signals) do
    {:emit_many, Enum.map(signals, fn
      {type, data} -> new(type, data)
      {type, data, meta} -> new(type, data, meta)
    end)}
  end

  @doc """
  Creates a halt result with a value.

  ## Examples

      iex> {:halt, value} = AgentForge.Signal.halt("done")
      iex> value == "done"
      true
  """
  def halt(value), do: {:halt, value}

  # Private Functions

  defp generate_trace_id do
    :crypto.strong_rand_bytes(8)
    |> Base.encode16(case: :lower)
  end
end
