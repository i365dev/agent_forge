defmodule AgentForge.Store do
  @moduledoc """
  A simple state container implementation using GenServer.
  Provides basic operations for state management.
  """
  use GenServer

  # Client API

  @doc """
  Starts the store process with an optional name.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Gets a value from the store.

  ## Examples

      iex> {:ok, _} = AgentForge.Store.start_link(name: :test_store)
      iex> AgentForge.Store.put(:test_store, :counter, 42)
      iex> AgentForge.Store.get(:test_store, :counter)
      {:ok, 42}
      iex> AgentForge.Store.get(:test_store, :nonexistent)
      {:error, :not_found}
  """
  def get(store \\ __MODULE__, key) do
    GenServer.call(store, {:get, key})
  end

  @doc """
  Puts a value in the store.

  ## Examples

      iex> {:ok, _} = AgentForge.Store.start_link(name: :test_store2)
      iex> AgentForge.Store.put(:test_store2, :counter, 42)
      :ok
  """
  def put(store \\ __MODULE__, key, value) do
    GenServer.cast(store, {:put, key, value})
  end

  @doc """
  Updates a value in the store using a function.

  ## Examples

      iex> {:ok, _} = AgentForge.Store.start_link(name: :test_store3)
      iex> AgentForge.Store.update(:test_store3, :counter, 0, &(&1 + 1))
      :ok
  """
  def update(store \\ __MODULE__, key, default, fun) when is_function(fun, 1) do
    GenServer.cast(store, {:update, key, default, fun})
  end

  @doc """
  Deletes a value from the store.

  ## Examples

      iex> {:ok, _} = AgentForge.Store.start_link(name: :test_store4)
      iex> AgentForge.Store.delete(:test_store4, :counter)
      :ok
  """
  def delete(store \\ __MODULE__, key) do
    GenServer.cast(store, {:delete, key})
  end

  # Server Callbacks

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    case Map.fetch(state, key) do
      {:ok, value} -> {:reply, {:ok, value}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_cast({:put, key, value}, state) do
    {:noreply, Map.put(state, key, value)}
  end

  @impl true
  def handle_cast({:update, key, default, fun}, state) do
    value =
      case Map.fetch(state, key) do
        {:ok, current} -> fun.(current)
        :error -> fun.(default)
      end

    {:noreply, Map.put(state, key, value)}
  end

  @impl true
  def handle_cast({:delete, key}, state) do
    {:noreply, Map.delete(state, key)}
  end
end
