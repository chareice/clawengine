defmodule ClawEngine.OpenClaw.AdminClient do
  @moduledoc """
  Minimal OpenClaw WebSocket RPC client for admin operations.
  """

  alias ClawEngine.Config
  alias ClawEngine.OpenClaw.Client
  alias ClawEngine.OpenClaw.ModelRef

  @callback health() :: {:ok, map()} | {:error, term()}
  @callback list_agents() :: {:ok, map()} | {:error, term()}
  @callback create_agent(map()) :: {:ok, map()} | {:error, term()}
  @callback update_agent(String.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback delete_agent(String.t()) :: {:ok, map()} | {:error, term()}
  @callback list_agent_files(String.t()) :: {:ok, map()} | {:error, term()}
  @callback get_agent_file(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  @callback set_agent_file(String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}

  @spec health() :: {:ok, map()} | {:error, term()}
  def health do
    request("health", %{})
  end

  @spec list_agents() :: {:ok, map()} | {:error, term()}
  def list_agents do
    request("agents.list", %{})
  end

  @spec create_agent(map()) :: {:ok, map()} | {:error, term()}
  def create_agent(%{name: name, workspace: workspace}) do
    request("agents.create", %{"name" => name, "workspace" => workspace})
    |> normalize_create_result()
  end

  @spec update_agent(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update_agent(agent_id, attrs) when is_binary(agent_id) and is_map(attrs) do
    params =
      attrs
      |> Enum.reduce(%{"agentId" => String.trim(agent_id)}, fn
        {:name, value}, acc when is_binary(value) ->
          Map.put(acc, "name", value)

        {:workspace, value}, acc when is_binary(value) ->
          Map.put(acc, "workspace", value)

        {:model_ref, value}, acc when is_binary(value) ->
          case ModelRef.normalize_for_gateway(value) do
            normalized when is_binary(normalized) -> Map.put(acc, "model", normalized)
            _other -> acc
          end

        {_key, _value}, acc ->
          acc
      end)

    request("agents.update", params)
  end

  @spec delete_agent(String.t()) :: {:ok, map()} | {:error, term()}
  def delete_agent(agent_id) do
    request("agents.delete", %{"agentId" => agent_id})
    |> normalize_delete_result()
  end

  @spec list_agent_files(String.t()) :: {:ok, map()} | {:error, term()}
  def list_agent_files(agent_id) do
    request("agents.files.list", %{"agentId" => agent_id})
  end

  @spec get_agent_file(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_agent_file(agent_id, name) do
    request("agents.files.get", %{"agentId" => agent_id, "name" => name})
  end

  @spec set_agent_file(String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def set_agent_file(agent_id, name, content) do
    request("agents.files.set", %{
      "agentId" => agent_id,
      "name" => name,
      "content" => content
    })
  end

  defp request(method, params) do
    gateway = Config.openclaw_gateway()

    with true <- gateway.token_present? || {:error, :missing_gateway_token},
         {:ok, payload} <-
           client().request(
             [
               url: Config.openclaw_gateway_ws_url(),
               token: gateway.token,
               timeout: Config.openclaw_admin_timeout_ms(),
               version: ClawEngine.version()
             ],
             method,
             params
           ) do
      {:ok, payload}
    end
  end

  defp normalize_create_result(
         {:ok, %{"agentId" => agent_id, "name" => name, "workspace" => workspace}}
       ) do
    {:ok, %{agent_id: agent_id, name: name, workspace: workspace}}
  end

  defp normalize_create_result(other), do: other

  defp normalize_delete_result({:ok, %{"agentId" => agent_id, "removedBindings" => removed}}) do
    {:ok, %{agent_id: agent_id, removed_bindings: removed}}
  end

  defp normalize_delete_result(other), do: other

  defp client do
    Application.get_env(:claw_engine, :openclaw_client, Client)
  end
end
