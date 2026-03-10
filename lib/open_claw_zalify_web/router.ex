defmodule OpenClawZalifyWeb.Router do
  @moduledoc false

  use Plug.Router

  alias OpenClawZalify.Agents.AgentRecord
  alias OpenClawZalify.Config
  alias OpenClawZalify.OpenClaw.Probe
  alias OpenClawZalifyWeb.ChatSocket

  plug(Plug.Logger)
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Jason)
  plug(:dispatch)

  get "/health" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      200,
      Jason.encode!(%{
        status: "ok",
        service: "openclaw-zalify",
        version: OpenClawZalify.version()
      })
    )
  end

  get "/ready" do
    gateway = Config.openclaw_gateway()

    case readiness(gateway) do
      {:ok, payload} ->
        json(conn, 200, payload)

      {:error, payload} ->
        json(conn, 503, payload)
    end
  end

  get "/ws/chat" do
    conn
    |> WebSockAdapter.upgrade(ChatSocket, [], timeout: Config.openclaw_chat_timeout_ms())
    |> halt()
  end

  get "/api/workspaces/:workspace_id/ai-agent" do
    case agents_service().get_workspace_agent(workspace_id) do
      {:ok, %AgentRecord{} = agent} ->
        json(conn, 200, %{agent: serialize_agent(agent)})

      {:ok, nil} ->
        json(conn, 404, %{error: "not_found"})

      {:error, reason} ->
        json(conn, 500, %{error: "internal_error", details: inspect(reason)})
    end
  end

  get "/api/workspaces/:workspace_id/ai-agent/files" do
    case agents_service().list_workspace_agent_files(workspace_id) do
      {:ok, %{agent: %AgentRecord{} = agent, files: files}} ->
        json(conn, 200, %{agent: serialize_agent(agent), files: files})

      {:ok, nil} ->
        json(conn, 404, %{error: "not_found"})

      {:error, {:validation, errors}} ->
        json(conn, 422, %{error: "validation_error", details: errors})

      {:error, {:connect_failed, reason}} ->
        json(conn, 502, %{error: "openclaw_connect_failed", details: reason})

      {:error, {:request_failed, reason}} ->
        json(conn, 502, %{error: "openclaw_request_failed", details: reason})

      {:error, reason} ->
        json(conn, 500, %{error: "internal_error", details: inspect(reason)})
    end
  end

  get "/api/workspaces/:workspace_id/ai-agent/files/:name" do
    case agents_service().get_workspace_agent_file(workspace_id, name) do
      {:ok, %{agent: %AgentRecord{} = agent, file: file}} ->
        json(conn, 200, %{agent: serialize_agent(agent), file: file})

      {:ok, nil} ->
        json(conn, 404, %{error: "not_found"})

      {:error, {:validation, errors}} ->
        json(conn, 422, %{error: "validation_error", details: errors})

      {:error, {:connect_failed, reason}} ->
        json(conn, 502, %{error: "openclaw_connect_failed", details: reason})

      {:error, {:request_failed, reason}} ->
        json(conn, 502, %{error: "openclaw_request_failed", details: reason})

      {:error, reason} ->
        json(conn, 500, %{error: "internal_error", details: inspect(reason)})
    end
  end

  post "/api/workspaces/:workspace_id/ai-agent/provision" do
    attrs = normalize_agent_attrs(conn.body_params)

    case agents_service().provision_workspace_agent(workspace_id, attrs) do
      {:ok, %{created?: created?, agent: %AgentRecord{} = agent}} ->
        status = if created?, do: 201, else: 200
        json(conn, status, %{created: created?, agent: serialize_agent(agent)})

      {:error, {:validation, errors}} ->
        json(conn, 422, %{error: "validation_error", details: errors})

      {:error, {:connect_failed, reason}} ->
        json(conn, 502, %{error: "openclaw_connect_failed", details: reason})

      {:error, {:request_failed, reason}} ->
        json(conn, 502, %{error: "openclaw_request_failed", details: reason})

      {:error, reason} ->
        json(conn, 500, %{error: "internal_error", details: inspect(reason)})
    end
  end

  delete "/api/workspaces/:workspace_id/ai-agent" do
    case agents_service().delete_workspace_agent(workspace_id) do
      {:ok, %{deleted?: true, agent: %AgentRecord{} = agent}} ->
        json(conn, 200, %{deleted: true, agent: serialize_agent(agent)})

      {:ok, %{deleted?: false}} ->
        json(conn, 404, %{error: "not_found"})

      {:error, {:validation, errors}} ->
        json(conn, 422, %{error: "validation_error", details: errors})

      {:error, {:connect_failed, reason}} ->
        json(conn, 502, %{error: "openclaw_connect_failed", details: reason})

      {:error, {:request_failed, reason}} ->
        json(conn, 502, %{error: "openclaw_request_failed", details: reason})

      {:error, reason} ->
        json(conn, 500, %{error: "internal_error", details: inspect(reason)})
    end
  end

  match _ do
    json(conn, 404, %{error: "not_found"})
  end

  defp readiness(%{endpoint: endpoint, token_present?: false}) do
    {:error,
     %{
       status: "not_ready",
       reason: "missing_gateway_token",
       gateway: %{
         url: "#{endpoint.scheme}://#{endpoint.host}:#{endpoint.port}#{endpoint.path}"
       }
     }}
  end

  defp readiness(%{endpoint: endpoint, token_present?: true}) do
    probe = Application.get_env(:openclaw_zalify, :openclaw_probe, Probe)

    case probe.check(endpoint, timeout: Config.openclaw_probe_timeout_ms()) do
      {:ok, details} ->
        {:ok,
         %{
           status: "ready",
           gateway: details
         }}

      {:error, details} ->
        {:error,
         %{
           status: "not_ready",
           reason: "gateway_unreachable",
           gateway: details
         }}
    end
  end

  defp normalize_agent_attrs(params) when is_map(params) do
    %{
      display_name: Map.get(params, "display_name"),
      role_prompt: Map.get(params, "role_prompt"),
      identity_md: Map.get(params, "identity_md"),
      soul_md: Map.get(params, "soul_md"),
      user_md: Map.get(params, "user_md"),
      model_ref: Map.get(params, "model_ref"),
      memory_enabled: Map.get(params, "memory_enabled", true)
    }
  end

  defp serialize_agent(%AgentRecord{} = agent) do
    %{
      workspace_id: agent.workspace_id,
      agent_id: agent.agent_id,
      status: agent.status,
      runtime_mode: agent.runtime_mode,
      workspace_path: agent.workspace_path,
      profile: %{
        display_name: agent.display_name,
        role_prompt: agent.role_prompt,
        identity_md: agent.identity_md,
        soul_md: agent.soul_md,
        user_md: agent.user_md,
        model_ref: agent.model_ref,
        memory_enabled: agent.memory_enabled
      }
    }
  end

  defp agents_service do
    Application.get_env(:openclaw_zalify, :agents_service, OpenClawZalify.Agents)
  end

  defp json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end
end
