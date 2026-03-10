defmodule OpenClawZalifyWeb.RouterAgentsTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test

  alias OpenClawZalify.Agents.AgentRecord
  alias OpenClawZalifyWeb.Router

  defmodule FakeAgentsService do
    def child_spec(_opts) do
      %{id: __MODULE__, start: {__MODULE__, :start_link, [[]]}}
    end

    def start_link(_opts) do
      Agent.start_link(fn -> %{records: %{}, files: %{}} end, name: __MODULE__)
    end

    def reset!, do: Agent.update(__MODULE__, fn _state -> %{records: %{}, files: %{}} end)

    def put!(workspace_id, record) do
      Agent.update(__MODULE__, fn state ->
        %{state | records: Map.put(state.records, workspace_id, record)}
      end)
    end

    def put_files!(workspace_id, files) do
      Agent.update(__MODULE__, fn state ->
        %{state | files: Map.put(state.files, workspace_id, files)}
      end)
    end

    def get_workspace_agent(workspace_id) do
      {:ok, Agent.get(__MODULE__, &Map.get(&1.records, workspace_id))}
    end

    def provision_workspace_agent(workspace_id, attrs) do
      record =
        %AgentRecord{
          workspace_id: workspace_id,
          agent_id: "zalify-#{workspace_id}",
          status: "active",
          runtime_mode: "shared",
          workspace_path: "/tmp/#{workspace_id}",
          display_name: attrs[:display_name] || "Default Agent",
          role_prompt: attrs[:role_prompt],
          identity_md: attrs[:identity_md],
          soul_md: attrs[:soul_md],
          user_md: attrs[:user_md],
          model_ref: attrs[:model_ref],
          memory_enabled: attrs[:memory_enabled]
        }

      put!(workspace_id, record)
      put_files!(workspace_id, default_files_for(record))
      {:ok, %{created?: true, agent: record}}
    end

    def delete_workspace_agent(workspace_id) do
      Agent.get_and_update(__MODULE__, fn state ->
        record = Map.get(state.records, workspace_id)

        result =
          case record do
            nil -> {:ok, %{deleted?: false, agent: nil}}
            _record -> {:ok, %{deleted?: true, agent: record}}
          end

        next_state = %{
          state
          | records: Map.delete(state.records, workspace_id),
            files: Map.delete(state.files, workspace_id)
        }

        {result, next_state}
      end)
    end

    def list_workspace_agent_files(workspace_id) do
      Agent.get(__MODULE__, fn state ->
        case Map.get(state.records, workspace_id) do
          nil ->
            {:ok, nil}

          record ->
            {:ok, %{agent: record, files: Map.get(state.files, workspace_id, [])}}
        end
      end)
    end

    def get_workspace_agent_file(workspace_id, name) do
      Agent.get(__MODULE__, fn state ->
        case Map.get(state.records, workspace_id) do
          nil ->
            {:ok, nil}

          record ->
            file =
              state.files
              |> Map.get(workspace_id, [])
              |> Enum.find(fn entry -> entry["name"] == name end)

            {:ok,
             %{
               agent: record,
               file:
                 file ||
                   %{"name" => name, "path" => "/tmp/#{workspace_id}/#{name}", "missing" => true}
             }}
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
    start_supervised!(FakeAgentsService)
    FakeAgentsService.reset!()

    original_service = Application.get_env(:openclaw_zalify, :agents_service)
    Application.put_env(:openclaw_zalify, :agents_service, FakeAgentsService)

    on_exit(fn ->
      Application.put_env(:openclaw_zalify, :agents_service, original_service)
    end)

    :ok
  end

  test "GET workspace agent returns 404 when no mapping exists" do
    conn =
      :get
      |> conn("/api/workspaces/shop-404/ai-agent")
      |> Router.call([])

    assert conn.status == 404
    assert Jason.decode!(conn.resp_body)["error"] == "not_found"
  end

  test "POST provision creates a workspace agent" do
    conn =
      :post
      |> conn(
        "/api/workspaces/shop-01/ai-agent/provision",
        Jason.encode!(%{"display_name" => "Shop 01 Agent", "memory_enabled" => true})
      )
      |> put_req_header("content-type", "application/json")
      |> Router.call([])

    assert conn.status == 201

    body = Jason.decode!(conn.resp_body)
    assert body["created"] == true
    assert body["agent"]["workspace_id"] == "shop-01"
    assert body["agent"]["profile"]["display_name"] == "Shop 01 Agent"
  end

  test "GET workspace agent returns the stored mapping" do
    FakeAgentsService.put!(
      "shop-02",
      %AgentRecord{
        workspace_id: "shop-02",
        agent_id: "zalify-shop-02",
        status: "active",
        runtime_mode: "shared",
        workspace_path: "/tmp/shop-02",
        display_name: "Stored Agent",
        identity_md: "# identity",
        soul_md: "# soul",
        user_md: "# user",
        memory_enabled: true
      }
    )

    conn =
      :get
      |> conn("/api/workspaces/shop-02/ai-agent")
      |> Router.call([])

    assert conn.status == 200

    body = Jason.decode!(conn.resp_body)
    assert body["agent"]["agent_id"] == "zalify-shop-02"
    assert body["agent"]["profile"]["display_name"] == "Stored Agent"
  end

  test "DELETE workspace agent removes the mapping" do
    FakeAgentsService.put!(
      "shop-delete",
      %AgentRecord{
        workspace_id: "shop-delete",
        agent_id: "zalify-shop-delete",
        status: "active",
        runtime_mode: "shared",
        workspace_path: "/tmp/shop-delete",
        display_name: "Delete Agent"
      }
    )

    conn =
      :delete
      |> conn("/api/workspaces/shop-delete/ai-agent")
      |> Router.call([])

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body)["deleted"] == true

    fetch_conn =
      :get
      |> conn("/api/workspaces/shop-delete/ai-agent")
      |> Router.call([])

    assert fetch_conn.status == 404
  end

  test "GET workspace agent files returns file metadata" do
    assert {:ok, %{created?: true}} =
             FakeAgentsService.provision_workspace_agent("shop-files", %{
               display_name: "Files Agent",
               identity_md: "# identity",
               soul_md: "# soul",
               user_md: "# user"
             })

    conn =
      :get
      |> conn("/api/workspaces/shop-files/ai-agent/files")
      |> Router.call([])

    assert conn.status == 200

    body = Jason.decode!(conn.resp_body)
    assert Enum.map(body["files"], & &1["name"]) == ["IDENTITY.md", "SOUL.md", "USER.md"]
  end

  test "GET workspace agent file returns the requested content" do
    assert {:ok, %{created?: true}} =
             FakeAgentsService.provision_workspace_agent("shop-file", %{
               display_name: "File Agent",
               identity_md: "# identity",
               soul_md: "# soul",
               user_md: "# user"
             })

    conn =
      :get
      |> conn("/api/workspaces/shop-file/ai-agent/files/IDENTITY.md")
      |> Router.call([])

    assert conn.status == 200

    body = Jason.decode!(conn.resp_body)
    assert body["file"]["name"] == "IDENTITY.md"
    assert body["file"]["content"] == "# identity"
  end
end
