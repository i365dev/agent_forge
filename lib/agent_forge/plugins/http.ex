defmodule AgentForge.Plugins.HTTP do
  @moduledoc """
  HTTP integration plugin for AgentForge.

  Provides tools for making HTTP requests in workflows.
  """

  @behaviour AgentForge.Plugin

  @impl true
  def init(_opts) do
    # Check for dependencies
    if Code.ensure_loaded?(Finch) do
      # Start Finch if not already started
      case Finch.start_link(name: __MODULE__.Finch) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
        error -> error
      end
    else
      {:error, :finch_not_installed}
    end
  end

  @impl true
  def register_tools(registry) do
    registry.register("http_get", &http_get/1)
    registry.register("http_post", &http_post/1)
    :ok
  end

  @impl true
  def metadata do
    %{
      name: "HTTP Plugin",
      description: "Provides HTTP client capabilities for AgentForge workflows",
      version: "1.0.0",
      author: "AgentForge Team",
      compatible_versions: ">= 0.1.0"
    }
  end

  # Tool implementations

  defp http_get(params) do
    if Code.ensure_loaded?(Finch) do
      url = Map.fetch!(params, "url")
      headers = Map.get(params, "headers", %{})

      request = Finch.build(:get, url, headers_to_list(headers))

      case Finch.request(request, __MODULE__.Finch) do
        {:ok, response} ->
          %{
            status: response.status,
            headers: headers_to_map(response.headers),
            body: response.body
          }

        {:error, reason} ->
          %{error: reason}
      end
    else
      %{error: :finch_not_installed, message: "Finch dependency is required for HTTP operations"}
    end
  end

  defp http_post(params) do
    if Code.ensure_loaded?(Finch) do
      url = Map.fetch!(params, "url")
      headers = Map.get(params, "headers", %{})
      body = Map.get(params, "body", "")

      request = Finch.build(:post, url, headers_to_list(headers), body)

      case Finch.request(request, __MODULE__.Finch) do
        {:ok, response} ->
          %{
            status: response.status,
            headers: headers_to_map(response.headers),
            body: response.body
          }

        {:error, reason} ->
          %{error: reason}
      end
    else
      %{error: :finch_not_installed, message: "Finch dependency is required for HTTP operations"}
    end
  end

  # Helper functions

  defp headers_to_list(headers) when is_map(headers) do
    Enum.map(headers, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp headers_to_map(headers) when is_list(headers) do
    Map.new(headers, fn {k, v} -> {k, v} end)
  end
end
