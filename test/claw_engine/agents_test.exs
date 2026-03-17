defmodule ClawEngine.AgentsTest do
  use ExUnit.Case, async: false

  alias ClawEngine.Agents
  alias ClawEngine.Agents.AgentRecord

  defmodule MemoryStore do
    @behaviour ClawEngine.Agents.Store

    def child_spec(_opts) do
      %{id: __MODULE__, start: {__MODULE__, :start_link, [[]]}}
    end

    def start_link(_opts) do
      Agent.start_link(fn -> %{} end, name: __MODULE__)
    end

    def reset!, do: Agent.update(__MODULE__, fn _state -> %{} end)

    @impl true
    def get_workspace_agent(workspace_id) do
      {:ok, Agent.get(__MODULE__, &Map.get(&1, workspace_id))}
    end

    @impl true
    def upsert_workspace_agent(attrs) do
      record =
        struct(AgentRecord, %{
          workspace_id: attrs.workspace_id,
          agent_id: attrs.agent_id,
          status: attrs.status,
          runtime_mode: attrs.runtime_mode,
          workspace_path: attrs.workspace_path,
          display_name: attrs.display_name,
          role_prompt: attrs.role_prompt,
          identity_md: attrs.identity_md,
          soul_md: attrs.soul_md,
          user_md: attrs.user_md,
          model_ref: attrs.model_ref,
          memory_enabled: attrs.memory_enabled
        })

      Agent.update(__MODULE__, &Map.put(&1, attrs.workspace_id, record))
      {:ok, record}
    end

    @impl true
    def delete_workspace_agent(workspace_id) do
      deleted =
        Agent.get_and_update(__MODULE__, fn state ->
          {Map.get(state, workspace_id), Map.delete(state, workspace_id)}
        end)

      {:ok, deleted}
    end
  end

  defmodule FakeAdminClient do
    def child_spec(_opts) do
      %{id: __MODULE__, start: {__MODULE__, :start_link, [[]]}}
    end

    def start_link(_opts) do
      Agent.start_link(
        fn ->
          %{
            create_calls: [],
            delete_calls: [],
            file_calls: [],
            fail_next_set_count: 0,
            workspaces: %{},
            files: %{}
          }
        end,
        name: __MODULE__
      )
    end

    def reset! do
      Agent.update(__MODULE__, fn _state ->
        %{
          create_calls: [],
          delete_calls: [],
          file_calls: [],
          fail_next_set_count: 0,
          workspaces: %{},
          files: %{}
        }
      end)
    end

    def create_calls, do: Agent.get(__MODULE__, & &1.create_calls)
    def delete_calls, do: Agent.get(__MODULE__, & &1.delete_calls)
    def file_calls, do: Agent.get(__MODULE__, & &1.file_calls)

    def fail_next_set! do
      Agent.update(__MODULE__, fn state ->
        %{state | fail_next_set_count: state.fail_next_set_count + 1}
      end)
    end

    def create_agent(%{name: name, workspace: workspace}) do
      Agent.update(__MODULE__, fn state ->
        %{
          state
          | create_calls: [%{name: name, workspace: workspace} | state.create_calls],
            workspaces: Map.put(state.workspaces, name, workspace),
            files: Map.put_new(state.files, name, %{})
        }
      end)

      {:ok, %{agent_id: name, name: name, workspace: workspace}}
    end

    def delete_agent(agent_id) do
      Agent.update(__MODULE__, fn state ->
        %{
          state
          | delete_calls: [agent_id | state.delete_calls],
            workspaces: Map.delete(state.workspaces, agent_id),
            files: Map.delete(state.files, agent_id)
        }
      end)

      {:ok, %{agent_id: agent_id, ok: true, removed_bindings: 0}}
    end

    def set_agent_file(agent_id, name, content) do
      Agent.get_and_update(__MODULE__, fn state ->
        next_state = %{
          state
          | file_calls: [%{agent_id: agent_id, name: name, content: content} | state.file_calls]
        }

        if state.fail_next_set_count > 0 do
          {{:error,
            {:request_failed, %{"code" => "INVALID_REQUEST", "message" => "unknown agent id"}}},
           %{next_state | fail_next_set_count: state.fail_next_set_count - 1}}
        else
          updated_state = %{
            next_state
            | files:
                Map.update(next_state.files, agent_id, %{name => content}, fn files ->
                  Map.put(files, name, content)
                end)
          }

          {{:ok, %{ok: true}}, updated_state}
        end
      end)
    end

    def list_agent_files(agent_id) do
      workspace = Agent.get(__MODULE__, &Map.get(&1.workspaces, agent_id, "/tmp/#{agent_id}"))

      files =
        Agent.get(__MODULE__, fn state ->
          state.files
          |> Map.get(agent_id, %{})
          |> Enum.map(fn {name, content} ->
            %{
              "name" => name,
              "path" => "#{workspace}/#{name}",
              "missing" => false,
              "size" => byte_size(content),
              "updatedAtMs" => 1
            }
          end)
          |> Enum.sort_by(& &1["name"])
        end)

      {:ok, %{"agentId" => agent_id, "workspace" => workspace, "files" => files}}
    end

    def get_agent_file(agent_id, name) do
      Agent.get(__MODULE__, fn state ->
        workspace = Map.get(state.workspaces, agent_id, "/tmp/#{agent_id}")
        content = state.files |> Map.get(agent_id, %{}) |> Map.get(name)

        file =
          if is_binary(content) do
            %{
              "name" => name,
              "path" => "#{workspace}/#{name}",
              "missing" => false,
              "size" => byte_size(content),
              "updatedAtMs" => 1,
              "content" => content
            }
          else
            %{
              "name" => name,
              "path" => "#{workspace}/#{name}",
              "missing" => true
            }
          end

        {:ok, %{"agentId" => agent_id, "workspace" => workspace, "file" => file}}
      end)
    end
  end

  setup do
    start_supervised!(MemoryStore)
    start_supervised!(FakeAdminClient)

    MemoryStore.reset!()
    FakeAdminClient.reset!()

    original_store = Application.get_env(:claw_engine, :agents_store)
    original_client = Application.get_env(:claw_engine, :openclaw_admin_client)
    original_retry_delays = Application.get_env(:claw_engine, :agents_file_sync_retry_delays_ms)

    Application.put_env(:claw_engine, :agents_store, MemoryStore)
    Application.put_env(:claw_engine, :openclaw_admin_client, FakeAdminClient)
    Application.put_env(:claw_engine, :agents_file_sync_retry_delays_ms, [0])

    on_exit(fn ->
      Application.put_env(:claw_engine, :agents_store, original_store)
      Application.put_env(:claw_engine, :openclaw_admin_client, original_client)
      Application.put_env(:claw_engine, :agents_file_sync_retry_delays_ms, original_retry_delays)
    end)

    :ok
  end

  test "provisions a new workspace agent and writes default files" do
    assert {:ok, %{created?: true, agent: agent}} =
             Agents.provision_workspace_agent("Shop 01", %{
               display_name: "Shop 01 Assistant"
             })

    assert agent.agent_id == "space-shop-01"
    assert agent.display_name == "Shop 01 Assistant"
    assert agent.workspace_path == "/home/node/.openclaw/workspace/spaces/space-shop-01"
    assert length(FakeAdminClient.create_calls()) == 1
    assert length(FakeAdminClient.file_calls()) == 3
  end

  test "returns the existing workspace agent on repeated provision calls" do
    assert {:ok, %{created?: true}} = Agents.provision_workspace_agent("shop-02", %{})

    assert {:ok, %{created?: false, agent: agent}} =
             Agents.provision_workspace_agent("shop-02", %{})

    assert agent.agent_id == "space-shop-02"
    assert length(FakeAdminClient.create_calls()) == 1
  end

  test "normalizes the workspace id into a stable agent name" do
    assert Agents.agent_name_for_workspace(" Demo / CN #1 ") == "space-demo-cn-1"
  end

  test "retries agent file sync when the gateway briefly returns unknown agent id" do
    FakeAdminClient.fail_next_set!()

    assert {:ok, %{created?: true, agent: agent}} =
             Agents.provision_workspace_agent("shop-retry", %{
               display_name: "Retry Agent"
             })

    assert agent.agent_id == "space-shop-retry"

    file_calls = FakeAdminClient.file_calls()
    assert length(file_calls) == 4
    assert Enum.count(file_calls, &(&1.name == "IDENTITY.md")) == 2
  end

  test "deletes an existing workspace agent and removes the local mapping" do
    assert {:ok, %{created?: true, agent: created}} =
             Agents.provision_workspace_agent("shop-delete", %{})

    assert {:ok, %{deleted?: true, agent: deleted}} =
             Agents.delete_workspace_agent("shop-delete")

    assert deleted.agent_id == created.agent_id
    assert FakeAdminClient.delete_calls() == ["space-shop-delete"]
    assert {:ok, nil} = Agents.get_workspace_agent("shop-delete")
  end

  test "lists and gets workspace agent files from OpenClaw" do
    assert {:ok, %{created?: true, agent: agent}} =
             Agents.provision_workspace_agent("shop-files", %{
               display_name: "Shop Files Agent"
             })

    assert {:ok, %{agent: listed_agent, files: files}} =
             Agents.list_workspace_agent_files("shop-files")

    assert listed_agent.agent_id == agent.agent_id
    assert Enum.map(files, & &1["name"]) == ["IDENTITY.md", "SOUL.md", "USER.md"]

    assert {:ok, %{agent: fetched_agent, file: file}} =
             Agents.get_workspace_agent_file("shop-files", "IDENTITY.md")

    assert fetched_agent.agent_id == agent.agent_id
    assert file["missing"] == false
    assert file["content"] =~ "Space ID: shop-files"
  end
end
