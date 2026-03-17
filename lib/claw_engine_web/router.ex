defmodule ClawEngineWeb.Router do
  @moduledoc false

  use Plug.Router

  alias ClawEngine.Agents.AgentRecord
  alias ClawEngine.Config
  alias ClawEngine.Engine.Space
  alias ClawEngine.OpenClaw.Probe
  alias ClawEngineWeb.ChatSocket

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
        service: "clawengine",
        version: ClawEngine.version()
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

  get "/api/instance" do
    with {:ok, instance} <- spaces_service().get_instance(),
         {:ok, spaces} <- spaces_service().list_spaces() do
      json(conn, 200, %{instance: serialize_instance(instance, length(spaces))})
    else
      {:error, reason} ->
        json(conn, 500, %{error: "internal_error", details: inspect(reason)})
    end
  end

  post "/api/instance/reload" do
    case spaces_service().reload_engine_config() do
      {:ok, snapshot} ->
        json(conn, 200, %{
          instance: serialize_instance(snapshot.instance, map_size(snapshot.spaces))
        })

      {:error, reason} ->
        json(conn, 422, %{error: "config_reload_failed", details: inspect(reason)})
    end
  end

  get "/api/spaces" do
    with {:ok, spaces} <- spaces_service().list_spaces() do
      json(conn, 200, %{spaces: Enum.map(spaces, &serialize_space/1)})
    else
      {:error, reason} ->
        json(conn, 500, %{error: "internal_error", details: inspect(reason)})
    end
  end

  get "/api/spaces/:space_id" do
    case spaces_service().get_space(space_id) do
      {:ok, %Space{} = space} ->
        agent_payload =
          case spaces_service().get_space_agent(space_id) do
            {:ok, %{agent: %AgentRecord{} = agent}} -> serialize_agent(agent)
            _other -> nil
          end

        json(conn, 200, %{space: serialize_space(space), agent: agent_payload})

      {:ok, nil} ->
        json(conn, 404, %{error: "not_found"})

      {:error, reason} ->
        json(conn, 500, %{error: "internal_error", details: inspect(reason)})
    end
  end

  get "/api/spaces/:space_id/agent" do
    handle_get_space_agent(conn, space_id)
  end

  get "/api/spaces/:space_id/agent/files" do
    handle_list_space_agent_files(conn, space_id)
  end

  get "/api/spaces/:space_id/agent/files/:name" do
    handle_get_space_agent_file(conn, space_id, name)
  end

  post "/api/spaces/:space_id/agent/provision" do
    handle_provision_space_agent(conn, space_id)
  end

  delete "/api/spaces/:space_id/agent" do
    handle_delete_space_agent(conn, space_id)
  end

  get "/api/workspaces/:workspace_id/ai-agent" do
    handle_get_space_agent(conn, workspace_id)
  end

  get "/api/workspaces/:workspace_id/ai-agent/files" do
    handle_list_space_agent_files(conn, workspace_id)
  end

  get "/api/workspaces/:workspace_id/ai-agent/files/:name" do
    handle_get_space_agent_file(conn, workspace_id, name)
  end

  post "/api/workspaces/:workspace_id/ai-agent/provision" do
    handle_provision_space_agent(conn, workspace_id)
  end

  delete "/api/workspaces/:workspace_id/ai-agent" do
    handle_delete_space_agent(conn, workspace_id)
  end

  match _ do
    json(conn, 404, %{error: "not_found"})
  end

  defp handle_get_space_agent(conn, space_id) do
    case spaces_service().get_space_agent(space_id) do
      {:ok, %{space: %Space{} = space, agent: %AgentRecord{} = agent}} ->
        json(conn, 200, %{space: serialize_space(space), agent: serialize_agent(agent)})

      {:ok, nil} ->
        json(conn, 404, %{error: "not_found"})

      {:error, {:validation, errors}} ->
        json(conn, 422, %{error: "validation_error", details: errors})

      {:error, {:connect_failed, reason}} ->
        json(conn, 502, %{error: "openclaw_connect_failed", details: reason})

      {:error, {:request_failed, reason}} ->
        json(conn, 502, %{error: "openclaw_request_failed", details: reason})

      {:error, {:not_found, :space}} ->
        json(conn, 404, %{error: "not_found"})

      {:error, reason} ->
        json(conn, 500, %{error: "internal_error", details: inspect(reason)})
    end
  end

  defp handle_list_space_agent_files(conn, space_id) do
    case spaces_service().list_space_agent_files(space_id) do
      {:ok, %{space: %Space{} = space, agent: %AgentRecord{} = agent, files: files}} ->
        json(conn, 200, %{
          space: serialize_space(space),
          agent: serialize_agent(agent),
          files: files
        })

      {:ok, nil} ->
        json(conn, 404, %{error: "not_found"})

      {:error, {:validation, errors}} ->
        json(conn, 422, %{error: "validation_error", details: errors})

      {:error, {:connect_failed, reason}} ->
        json(conn, 502, %{error: "openclaw_connect_failed", details: reason})

      {:error, {:request_failed, reason}} ->
        json(conn, 502, %{error: "openclaw_request_failed", details: reason})

      {:error, {:not_found, :space}} ->
        json(conn, 404, %{error: "not_found"})

      {:error, reason} ->
        json(conn, 500, %{error: "internal_error", details: inspect(reason)})
    end
  end

  defp handle_get_space_agent_file(conn, space_id, name) do
    case spaces_service().get_space_agent_file(space_id, name) do
      {:ok, %{space: %Space{} = space, agent: %AgentRecord{} = agent, file: file}} ->
        json(conn, 200, %{
          space: serialize_space(space),
          agent: serialize_agent(agent),
          file: file
        })

      {:ok, nil} ->
        json(conn, 404, %{error: "not_found"})

      {:error, {:validation, errors}} ->
        json(conn, 422, %{error: "validation_error", details: errors})

      {:error, {:connect_failed, reason}} ->
        json(conn, 502, %{error: "openclaw_connect_failed", details: reason})

      {:error, {:request_failed, reason}} ->
        json(conn, 502, %{error: "openclaw_request_failed", details: reason})

      {:error, {:not_found, :space}} ->
        json(conn, 404, %{error: "not_found"})

      {:error, reason} ->
        json(conn, 500, %{error: "internal_error", details: inspect(reason)})
    end
  end

  defp handle_provision_space_agent(conn, space_id) do
    attrs = normalize_agent_attrs(conn.body_params)

    case spaces_service().provision_space_agent(space_id, attrs) do
      {:ok, %{created?: created?, space: %Space{} = space, agent: %AgentRecord{} = agent}} ->
        status = if created?, do: 201, else: 200

        json(conn, status, %{
          created: created?,
          space: serialize_space(space),
          agent: serialize_agent(agent)
        })

      {:error, {:validation, errors}} ->
        json(conn, 422, %{error: "validation_error", details: errors})

      {:error, {:connect_failed, reason}} ->
        json(conn, 502, %{error: "openclaw_connect_failed", details: reason})

      {:error, {:request_failed, reason}} ->
        json(conn, 502, %{error: "openclaw_request_failed", details: reason})

      {:error, {:not_found, :space}} ->
        json(conn, 404, %{error: "not_found"})

      {:error, reason} ->
        json(conn, 500, %{error: "internal_error", details: inspect(reason)})
    end
  end

  defp handle_delete_space_agent(conn, space_id) do
    case spaces_service().delete_space_agent(space_id) do
      {:ok, %{deleted?: true, space: space, agent: %AgentRecord{} = agent}} ->
        body = %{deleted: true, agent: serialize_agent(agent)}

        body =
          if is_struct(space, Space),
            do: Map.put(body, :space, serialize_space(space)),
            else: body

        json(conn, 200, body)

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
    probe = Application.get_env(:claw_engine, :openclaw_probe, Probe)

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
      space_id: agent.workspace_id,
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

  defp serialize_space(%Space{} = space) do
    %{
      id: space.id,
      name: space.name,
      slug: space.slug,
      display_name: space.display_name,
      agent_name: space.agent_name,
      workspace_path: space.workspace_path,
      template_set: space.template_set,
      model_profile_id: space.model_profile_id,
      model_ref: space.model_ref,
      reasoning_level: space.reasoning_level,
      timeout_ms: space.timeout_ms,
      memory_enabled: space.memory_enabled,
      variables: space.variables
    }
  end

  defp serialize_instance(instance, spaces_count) do
    %{
      id: instance.id,
      name: instance.name,
      agent_name_template: instance.agent_name_template,
      workspace_path_template: instance.workspace_path_template,
      default_template_set: instance.default_template_set,
      default_model_profile_id: instance.default_model_profile_id,
      default_tool_profile_id: instance.default_tool_profile_id,
      default_memory_enabled: instance.default_memory_enabled,
      config_root: instance.config_root,
      spaces_count: spaces_count
    }
  end

  defp spaces_service do
    Application.get_env(:claw_engine, :spaces_service, ClawEngine.Spaces)
  end

  defp json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end
end
