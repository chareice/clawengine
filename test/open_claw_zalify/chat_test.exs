defmodule OpenClawZalify.ChatTest do
  use ExUnit.Case, async: false

  alias OpenClawZalify.Agents.AgentRecord
  alias OpenClawZalify.Chat
  alias OpenClawZalify.Chat.SessionRecord

  defmodule MemoryChatStore do
    @behaviour OpenClawZalify.Chat.Store

    def child_spec(_opts) do
      %{id: __MODULE__, start: {__MODULE__, :start_link, [[]]}}
    end

    def start_link(_opts) do
      Agent.start_link(fn -> %{} end, name: __MODULE__)
    end

    def reset!, do: Agent.update(__MODULE__, fn _state -> %{} end)

    @impl true
    def get_session(session_id) do
      {:ok, Agent.get(__MODULE__, &Map.get(&1, session_id))}
    end

    @impl true
    def create_session(attrs) do
      session =
        struct(SessionRecord, %{
          id: attrs.id,
          workspace_id: attrs.workspace_id,
          agent_id: attrs.agent_id,
          openclaw_session_key: attrs.openclaw_session_key,
          status: attrs.status
        })

      Agent.update(__MODULE__, &Map.put(&1, session.id, session))
      {:ok, session}
    end
  end

  defmodule FakeAgentsService do
    def child_spec(_opts) do
      %{id: __MODULE__, start: {__MODULE__, :start_link, [[]]}}
    end

    def start_link(_opts) do
      Agent.start_link(fn -> %{records: %{}} end, name: __MODULE__)
    end

    def reset!, do: Agent.update(__MODULE__, fn _state -> %{records: %{}} end)

    def put!(workspace_id, %AgentRecord{} = record) do
      Agent.update(__MODULE__, fn state ->
        %{state | records: Map.put(state.records, workspace_id, record)}
      end)
    end

    def get_workspace_agent(workspace_id) do
      {:ok, Agent.get(__MODULE__, &Map.get(&1.records, workspace_id))}
    end

    def provision_workspace_agent(workspace_id, _attrs) do
      record = %AgentRecord{
        workspace_id: workspace_id,
        agent_id: "zalify-#{workspace_id}",
        status: "active",
        runtime_mode: "shared",
        workspace_path: "/tmp/#{workspace_id}",
        display_name: "Agent #{workspace_id}",
        memory_enabled: true
      }

      put!(workspace_id, record)
      {:ok, %{created?: true, agent: record}}
    end
  end

  defmodule FakeChatGateway do
    def child_spec(_opts) do
      %{id: __MODULE__, start: {__MODULE__, :start_link, [[]]}}
    end

    def start_link(_opts) do
      Agent.start_link(
        fn ->
          %{patch_calls: [], history_calls: [], abort_calls: []}
        end,
        name: __MODULE__
      )
    end

    def reset! do
      Agent.update(__MODULE__, fn _state ->
        %{patch_calls: [], history_calls: [], abort_calls: []}
      end)
    end

    def patch_calls, do: Agent.get(__MODULE__, &Enum.reverse(&1.patch_calls))
    def history_calls, do: Agent.get(__MODULE__, &Enum.reverse(&1.history_calls))
    def abort_calls, do: Agent.get(__MODULE__, &Enum.reverse(&1.abort_calls))

    def patch_session_model(session_key, model_ref) do
      Agent.update(__MODULE__, fn state ->
        %{
          state
          | patch_calls: [%{session_key: session_key, model_ref: model_ref} | state.patch_calls]
        }
      end)

      {:ok, %{"ok" => true}}
    end

    def chat_history(session_key, limit) do
      Agent.update(__MODULE__, fn state ->
        %{
          state
          | history_calls: [%{session_key: session_key, limit: limit} | state.history_calls]
        }
      end)

      {:ok,
       %{
         "messages" => [
           %{"role" => "user", "content" => [%{"type" => "text", "text" => "hello"}]}
         ]
       }}
    end

    def abort_chat(session_key, run_id) do
      Agent.update(__MODULE__, fn state ->
        %{state | abort_calls: [%{session_key: session_key, run_id: run_id} | state.abort_calls]}
      end)

      {:ok, %{"aborted" => true, "runIds" => Enum.reject([run_id], &is_nil/1)}}
    end
  end

  defmodule FakeChatClient do
    def child_spec(_opts) do
      %{id: __MODULE__, start: {__MODULE__, :start_link, [[]]}}
    end

    def start_link(_opts) do
      Agent.start_link(fn -> %{calls: []} end, name: __MODULE__)
    end

    def reset!, do: Agent.update(__MODULE__, fn _state -> %{calls: []} end)
    def calls, do: Agent.get(__MODULE__, &Enum.reverse(&1.calls))

    def start_stream(opts) do
      Agent.update(__MODULE__, fn state ->
        %{state | calls: [Enum.into(opts, %{}) | state.calls]}
      end)

      send(
        Keyword.fetch!(opts, :stream_to),
        {:openclaw_chat_stream, Keyword.fetch!(opts, :stream_ref),
         {:run_started,
          %{
            session_id: Keyword.fetch!(opts, :session_id),
            session_key: Keyword.fetch!(opts, :session_key),
            run_id: "run-test-1",
            status: "started"
          }}}
      )

      {:ok, spawn(fn -> :ok end)}
    end
  end

  setup do
    start_supervised!(MemoryChatStore)
    start_supervised!(FakeAgentsService)
    start_supervised!(FakeChatGateway)
    start_supervised!(FakeChatClient)

    MemoryChatStore.reset!()
    FakeAgentsService.reset!()
    FakeChatGateway.reset!()
    FakeChatClient.reset!()

    original_env = %{
      agents_service: Application.get_env(:openclaw_zalify, :agents_service),
      chat_store: Application.get_env(:openclaw_zalify, :chat_store),
      openclaw_chat_gateway: Application.get_env(:openclaw_zalify, :openclaw_chat_gateway),
      openclaw_chat_client: Application.get_env(:openclaw_zalify, :openclaw_chat_client)
    }

    Application.put_env(:openclaw_zalify, :agents_service, FakeAgentsService)
    Application.put_env(:openclaw_zalify, :chat_store, MemoryChatStore)
    Application.put_env(:openclaw_zalify, :openclaw_chat_gateway, FakeChatGateway)
    Application.put_env(:openclaw_zalify, :openclaw_chat_client, FakeChatClient)

    on_exit(fn ->
      Enum.each(original_env, fn {key, value} ->
        Application.put_env(:openclaw_zalify, key, value)
      end)
    end)

    :ok
  end

  test "send_message creates a chat session and starts a stream" do
    stream_ref = %{request_id: "req-1"}

    assert {:ok, %{session: session, agent: agent}} =
             Chat.send_message("shop-chat", nil, "Hello world",
               stream_to: self(),
               stream_ref: stream_ref
             )

    assert session.workspace_id == "shop-chat"
    assert session.agent_id == "zalify-shop-chat"
    assert session.openclaw_session_key == "agent:zalify-shop-chat:web:direct:#{session.id}"
    assert agent.agent_id == "zalify-shop-chat"

    assert_receive {:openclaw_chat_stream, ^stream_ref,
                    {:run_started, %{session_id: session_id, run_id: "run-test-1"}}}

    assert session_id == session.id

    [call] = FakeChatClient.calls()
    assert call.session_id == session.id
    assert call.message == "Hello world"
  end

  test "send_message applies the agent model override before streaming" do
    FakeAgentsService.put!(
      "shop-model",
      %AgentRecord{
        workspace_id: "shop-model",
        agent_id: "zalify-shop-model",
        status: "active",
        runtime_mode: "shared",
        workspace_path: "/tmp/shop-model",
        display_name: "Model Agent",
        model_ref: "deepseek/deepseek-chat",
        memory_enabled: true
      }
    )

    assert {:ok, %{session: session}} =
             Chat.send_message("shop-model", nil, "Use deepseek",
               stream_to: self(),
               stream_ref: %{}
             )

    assert [
             %{
               session_key: session_key,
               model_ref: "deepseek/deepseek-chat"
             }
           ] = FakeChatGateway.patch_calls()

    assert session_key == session.openclaw_session_key
  end

  test "get_history loads the stored session and delegates to OpenClaw" do
    assert {:ok, %{session: session}} =
             Chat.send_message("shop-history", nil, "History seed",
               stream_to: self(),
               stream_ref: %{}
             )

    assert {:ok, %{session: fetched_session, history: history}} =
             Chat.get_history(session.id, 25)

    assert fetched_session.id == session.id
    assert hd(history["messages"])["role"] == "user"
    assert [%{limit: 25, session_key: session_key}] = FakeChatGateway.history_calls()
    assert session_key == session.openclaw_session_key
  end

  test "abort_run delegates to OpenClaw" do
    assert {:ok, %{session: session}} =
             Chat.send_message("shop-abort", nil, "Abort seed",
               stream_to: self(),
               stream_ref: %{}
             )

    assert {:ok, %{session: aborted_session, result: result}} =
             Chat.abort_run(session.id, "run-123")

    assert aborted_session.id == session.id
    assert result["aborted"] == true
    assert [%{run_id: "run-123", session_key: session_key}] = FakeChatGateway.abort_calls()
    assert session_key == session.openclaw_session_key
  end
end
