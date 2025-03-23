defmodule AgentForge.StoreTest do
  use ExUnit.Case, async: true
  doctest AgentForge.Store

  alias AgentForge.Store

  setup do
    # Use a unique name for each test to allow parallel testing
    store_name = String.to_atom("store_#{System.unique_integer()}")
    start_supervised!({Store, name: store_name})
    %{store: store_name}
  end

  describe "put/2 and get/1" do
    test "stores and retrieves values", %{store: store} do
      assert :ok == Store.put(store, :key1, "value1")
      assert {:ok, "value1"} == Store.get(store, :key1)
    end

    test "returns error for non-existent keys", %{store: store} do
      assert {:error, :not_found} == Store.get(store, :nonexistent)
    end

    test "overwrites existing values", %{store: store} do
      Store.put(store, :key1, "value1")
      Store.put(store, :key1, "value2")
      assert {:ok, "value2"} == Store.get(store, :key1)
    end
  end

  describe "update/3" do
    test "updates existing values with function", %{store: store} do
      Store.put(store, :counter, 1)
      Store.update(store, :counter, 0, &(&1 + 1))
      assert {:ok, 2} == Store.get(store, :counter)
    end

    test "initializes with default for non-existent keys", %{store: store} do
      Store.update(store, :new_counter, 0, &(&1 + 1))
      assert {:ok, 1} == Store.get(store, :new_counter)
    end

    test "handles complex updates", %{store: store} do
      Store.put(store, :map, %{count: 0})
      Store.update(store, :map, %{}, &Map.update(&1, :count, 1, fn c -> c + 1 end))
      assert {:ok, %{count: 1}} == Store.get(store, :map)
    end
  end

  describe "delete/1" do
    test "removes values from store", %{store: store} do
      Store.put(store, :key1, "value1")
      assert :ok == Store.delete(store, :key1)
      assert {:error, :not_found} == Store.get(store, :key1)
    end

    test "succeeds for non-existent keys", %{store: store} do
      assert :ok == Store.delete(store, :nonexistent)
    end
  end

  describe "concurrent operations" do
    test "handles concurrent updates safely", %{store: store} do
      Store.put(store, :counter, 0)

      tasks =
        for _ <- 1..10 do
          Task.async(fn ->
            Store.update(store, :counter, 0, &(&1 + 1))
          end)
        end

      Task.await_many(tasks)
      {:ok, final_value} = Store.get(store, :counter)
      assert final_value == 10
    end
  end
end
