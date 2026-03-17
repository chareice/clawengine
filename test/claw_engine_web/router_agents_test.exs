defmodule ClawEngineWeb.RouterAgentsTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test

  alias ClawEngine.Agents.AgentRecord
  alias ClawEngine.Engine.Instance
  alias ClawEngine.Engine.Snapshot
  alias ClawEngine.Engine.Space
  alias ClawEngineWeb.Router

  defmodule FakeSpacesService do
    def child_spec(_opts) do
      %{id: __MODULE__, start: {__MODULE__, :start_link, [[]]}}
    end

    def start_link(_opts) do
      Agent.start_link(fn -> %{spaces: %{}, agents: %{}, files: %{}} end, name: __MODULE__)
    end

    def reset!,
      do: Agent.update(__MODULE__, fn _state -> %{spaces: %{}, agents: %{}, files: %{}} end)

    def put_space!(%Space{} = space) do
      Agent.update(__MODULE__, fn state ->
        %{state | spaces: Map.put(state.spaces, space.id, space)}
      end)
    end

    def put_agent!(space_id, %AgentRecord{} = record) do
      Agent.update(__MODULE__, fn state ->
        %{state | agents: Map.put(state.agents, space_id, record)}
      end)
    end

    def put_files!(space_id, files) do
      Agent.update(__MODULE__, fn state ->
        %{state | files: Map.put(state.files, space_id, files)}
      end)
    end

    def get_instance do
      {:ok,
       %Instance{
         id: "demo-business",
         name: "Demo Business",
         agent_name_template: "{{instance.id}}-{{space.slug}}",
         workspace_path_template: "/tmp/demo-business/{{space.slug}}",
         default_template_set: "merchant-support",
         default_model_profile_id: "default",
         default_tool_profile_id: "default",
         default_memory_enabled: true,
         config_root: "/tmp/engine"
       }}
    end

    def reload_engine_config do
      {:ok,
       %Snapshot{
         config_root: "/tmp/engine",
         instance: elem(get_instance(), 1),
         spaces: Agent.get(__MODULE__, & &1.spaces),
         model_profiles: %{},
         loaded_at: DateTime.utc_now()
       }}
    end

    def list_spaces do
      {:ok,
       Agent.get(__MODULE__, fn state ->
         state.spaces
         |> Map.values()
         |> Enum.sort_by(fn space -> space.id end)
       end)}
    end

    def get_space(space_id) do
      {:ok, Agent.get(__MODULE__, &Map.get(&1.spaces, space_id))}
    end

    def get_space_agent(space_id) do
      Agent.get(__MODULE__, fn state ->
        case {Map.get(state.spaces, space_id), Map.get(state.agents, space_id)} do
          {%Space{} = space, %AgentRecord{} = agent} -> {:ok, %{space: space, agent: agent}}
          {%Space{}, nil} -> {:ok, nil}
          {nil, _agent} -> {:error, {:not_found, :space}}
        end
      end)
    end

    def provision_space_agent(space_id, attrs) do
      Agent.get_and_update(__MODULE__, fn state ->
        case Map.get(state.spaces, space_id) do
          nil ->
            {{:error, {:not_found, :space}}, state}

          %Space{} = space ->
            existing = Map.get(state.agents, space_id)

            record =
              existing ||
                %AgentRecord{
                  workspace_id: space_id,
                  agent_id: space.agent_name,
                  status: "active",
                  runtime_mode: "shared",
                  workspace_path: space.workspace_path,
                  display_name: attrs[:display_name] || space.display_name,
                  role_prompt: attrs[:role_prompt] || space.role_prompt,
                  identity_md: attrs[:identity_md] || space.identity_md,
                  soul_md: attrs[:soul_md] || space.soul_md,
                  user_md: attrs[:user_md] || space.user_md,
                  model_ref: attrs[:model_ref] || space.model_ref,
                  memory_enabled: Map.get(attrs, :memory_enabled, space.memory_enabled)
                }

            files = default_files_for(record)

            result = {:ok, %{created?: is_nil(existing), space: space, agent: record}}

            next_state = %{
              state
              | agents: Map.put(state.agents, space_id, record),
                files: Map.put(state.files, space_id, files)
            }

            {result, next_state}
        end
      end)
    end

    def delete_space_agent(space_id) do
      Agent.get_and_update(__MODULE__, fn state ->
        result =
          case Map.get(state.agents, space_id) do
            nil ->
              {:ok, %{deleted?: false, space: Map.get(state.spaces, space_id), agent: nil}}

            %AgentRecord{} = record ->
              {:ok, %{deleted?: true, space: Map.get(state.spaces, space_id), agent: record}}
          end

        next_state = %{
          state
          | agents: Map.delete(state.agents, space_id),
            files: Map.delete(state.files, space_id)
        }

        {result, next_state}
      end)
    end

    def list_space_agent_files(space_id) do
      Agent.get(__MODULE__, fn state ->
        case {Map.get(state.spaces, space_id), Map.get(state.agents, space_id)} do
          {%Space{} = space, %AgentRecord{} = agent} ->
            {:ok, %{space: space, agent: agent, files: Map.get(state.files, space_id, [])}}

          {%Space{}, nil} ->
            {:ok, nil}

          {nil, _agent} ->
            {:error, {:not_found, :space}}
        end
      end)
    end

    def get_space_agent_file(space_id, name) do
      Agent.get(__MODULE__, fn state ->
        case {Map.get(state.spaces, space_id), Map.get(state.agents, space_id)} do
          {%Space{} = space, %AgentRecord{} = agent} ->
            file =
              state.files
              |> Map.get(space_id, [])
              |> Enum.find(fn entry -> entry["name"] == name end)

            {:ok,
             %{
               space: space,
               agent: agent,
               file:
                 file ||
                   %{"name" => name, "path" => "/tmp/#{space_id}/#{name}", "missing" => true}
             }}

          {%Space{}, nil} ->
            {:ok, nil}

          {nil, _agent} ->
            {:error, {:not_found, :space}}
        end
      end)
    end

    defp default_files_for(record) do
      [
        %{
          "name" => "IDENTITY.md",
          "path" => "/tmp/#{record.workspace_id}/IDENTITY.md",
          "missing" => false,
          "size" => byte_size(record.identity_md || ""),
          "updatedAtMs" => 1,
          "content" => record.identity_md
        },
        %{
          "name" => "SOUL.md",
          "path" => "/tmp/#{record.workspace_id}/SOUL.md",
          "missing" => false,
          "size" => byte_size(record.soul_md || ""),
          "updatedAtMs" => 1,
          "content" => record.soul_md
        },
        %{
          "name" => "USER.md",
          "path" => "/tmp/#{record.workspace_id}/USER.md",
          "missing" => false,
          "size" => byte_size(record.user_md || ""),
          "updatedAtMs" => 1,
          "content" => record.user_md
        }
      ]
    end
  end

  setup do
    start_supervised!(FakeSpacesService)
    FakeSpacesService.reset!()

    FakeSpacesService.put_space!(%Space{
      id: "shop-01",
      name: "Shop 01",
      slug: "shop-01",
      display_name: "Shop 01 Assistant",
      agent_name: "demo-business-shop-01",
      workspace_path: "/tmp/demo-business/shop-01",
      template_set: "merchant-support",
      model_profile_id: "default",
      tool_profile_id: "default",
      model_ref: nil,
      reasoning_level: "off",
      timeout_ms: 60_000,
      role_prompt: nil,
      memory_enabled: true,
      identity_md: "# identity",
      soul_md: "# soul",
      user_md: "# user",
      variables: %{"region" => "sg"},
      raw: %{}
    })

    FakeSpacesService.put_space!(%Space{
      id: "shop-02",
      name: "Shop 02",
      slug: "shop-02",
      display_name: "Stored Agent",
      agent_name: "demo-business-shop-02",
      workspace_path: "/tmp/demo-business/shop-02",
      template_set: "merchant-support",
      model_profile_id: "default",
      tool_profile_id: "default",
      model_ref: "deepseek/deepseek-chat",
      reasoning_level: "off",
      timeout_ms: 60_000,
      role_prompt: nil,
      memory_enabled: true,
      identity_md: "# identity",
      soul_md: "# soul",
      user_md: "# user",
      variables: %{},
      raw: %{}
    })

    original_spaces_service = Application.get_env(:claw_engine, :spaces_service)
    Application.put_env(:claw_engine, :spaces_service, FakeSpacesService)

    on_exit(fn ->
      Application.put_env(:claw_engine, :spaces_service, original_spaces_service)
    end)

    :ok
  end

  test "GET instance returns the loaded business config" do
    conn =
      :get
      |> conn("/api/instance")
      |> Router.call([])

    assert conn.status == 200

    body = Jason.decode!(conn.resp_body)
    assert body["instance"]["id"] == "demo-business"
    assert body["instance"]["spaces_count"] == 2
  end

  test "GET spaces returns configured spaces" do
    conn =
      :get
      |> conn("/api/spaces")
      |> Router.call([])

    assert conn.status == 200

    body = Jason.decode!(conn.resp_body)
    assert Enum.map(body["spaces"], & &1["id"]) == ["shop-01", "shop-02"]
  end

  test "POST provision creates a space agent from the engine config" do
    conn =
      :post
      |> conn(
        "/api/spaces/shop-01/agent/provision",
        Jason.encode!(%{"display_name" => "Shop 01 Agent", "memory_enabled" => true})
      )
      |> put_req_header("content-type", "application/json")
      |> Router.call([])

    assert conn.status == 201

    body = Jason.decode!(conn.resp_body)
    assert body["created"] == true
    assert body["space"]["id"] == "shop-01"
    assert body["agent"]["space_id"] == "shop-01"
    assert body["agent"]["profile"]["display_name"] == "Shop 01 Agent"
  end

  test "GET space returns the configured space and agent snapshot" do
    assert {:ok, %{created?: true}} = FakeSpacesService.provision_space_agent("shop-02", %{})

    conn =
      :get
      |> conn("/api/spaces/shop-02")
      |> Router.call([])

    assert conn.status == 200

    body = Jason.decode!(conn.resp_body)
    assert body["space"]["id"] == "shop-02"
    assert body["agent"]["agent_id"] == "demo-business-shop-02"
  end

  test "DELETE space agent removes the mapping" do
    assert {:ok, %{created?: true}} = FakeSpacesService.provision_space_agent("shop-01", %{})

    conn =
      :delete
      |> conn("/api/spaces/shop-01/agent")
      |> Router.call([])

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body)["deleted"] == true

    fetch_conn =
      :get
      |> conn("/api/spaces/shop-01/agent")
      |> Router.call([])

    assert fetch_conn.status == 404
  end

  test "GET space agent files returns file metadata" do
    assert {:ok, %{created?: true}} = FakeSpacesService.provision_space_agent("shop-01", %{})

    conn =
      :get
      |> conn("/api/spaces/shop-01/agent/files")
      |> Router.call([])

    assert conn.status == 200

    body = Jason.decode!(conn.resp_body)
    assert Enum.map(body["files"], & &1["name"]) == ["IDENTITY.md", "SOUL.md", "USER.md"]
  end

  test "legacy workspace route aliases the generic space provision flow" do
    conn =
      :post
      |> conn("/api/workspaces/shop-01/ai-agent/provision", Jason.encode!(%{}))
      |> put_req_header("content-type", "application/json")
      |> Router.call([])

    assert conn.status == 201

    body = Jason.decode!(conn.resp_body)
    assert body["space"]["id"] == "shop-01"
    assert body["agent"]["space_id"] == "shop-01"
  end
end
