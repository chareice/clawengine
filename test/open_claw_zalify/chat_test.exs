defmodule OpenClawZalify.ChatTest do
  use ExUnit.Case, async: false

  alias OpenClawZalify.Agents.AgentRecord
  alias OpenClawZalify.Chat
  alias OpenClawZalify.Chat.SessionRecord
  alias OpenClawZalify.Engine.Space

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

  defmodule FakeSpacesService do
    def child_spec(_opts) do
      %{id: __MODULE__, start: {__MODULE__, :start_link, [[]]}}
    end

    def start_link(_opts) do
      Agent.start_link(fn -> %{spaces: %{}, agents: %{}} end, name: __MODULE__)
    end

    def reset!, do: Agent.update(__MODULE__, fn _state -> %{spaces: %{}, agents: %{}} end)

    def put!(space_id, %Space{} = space, %AgentRecord{} = agent) do
      Agent.update(__MODULE__, fn state ->
        %{
          state
          | spaces: Map.put(state.spaces, space_id, space),
            agents: Map.put(state.agents, space_id, agent)
        }
      end)
    end

    def get_space_agent(space_id) do
      {:ok,
       Agent.get(__MODULE__, fn state ->
         case {Map.get(state.spaces, space_id), Map.get(state.agents, space_id)} do
           {%Space{} = space, %AgentRecord{} = agent} -> %{space: space, agent: agent}
           _other -> nil
         end
       end)}
    end

    def provision_space_agent(space_id, _attrs) do
      space = build_space(space_id, %{})

      agent =
        %AgentRecord{
          workspace_id: space_id,
          agent_id: "space-#{space_id}",
          status: "active",
          runtime_mode: "shared",
          workspace_path: "/tmp/#{space_id}",
          display_name: "#{space.name} Assistant",
          model_ref: space.model_ref,
          memory_enabled: space.memory_enabled
        }

      put!(space_id, space, agent)
      {:ok, %{created?: true, space: space, agent: agent}}
    end

    def build_space(space_id, overrides) do
      struct(
        Space,
        Map.merge(
          %{
            id: space_id,
            name: "Space #{space_id}",
            slug: space_id,
            display_name: "Space #{space_id} Assistant",
            agent_name: "space-#{space_id}",
            workspace_path: "/tmp/#{space_id}",
            template_set: "merchant-support",
            model_profile_id: "default",
            tool_profile_id: "default",
            model_ref: nil,
            reasoning_level: nil,
            timeout_ms: 60_000,
            role_prompt: nil,
            memory_enabled: true,
            identity_md: "# identity",
            soul_md: "# soul",
            user_md: "# user",
            variables: %{},
            raw: %{}
          },
          overrides
        )
      )
    end
  end

  defmodule FakeChatGateway do
    def child_spec(_opts) do
      %{id: __MODULE__, start: {__MODULE__, :start_link, [[]]}}
    end

    def start_link(_opts) do
      Agent.start_link(
        fn ->
          %{patch_calls: [], history_calls: [], abort_calls: [], patch_results: []}
        end,
        name: __MODULE__
      )
    end

    def reset! do
      Agent.update(__MODULE__, fn _state ->
        %{patch_calls: [], history_calls: [], abort_calls: [], patch_results: []}
      end)
    end

    def patch_calls, do: Agent.get(__MODULE__, &Enum.reverse(&1.patch_calls))
    def history_calls, do: Agent.get(__MODULE__, &Enum.reverse(&1.history_calls))
    def abort_calls, do: Agent.get(__MODULE__, &Enum.reverse(&1.abort_calls))
    def set_patch_results(results) when is_list(results), do: Agent.update(__MODULE__, &Map.put(&1, :patch_results, results))

    def patch_session(session_key, attrs) do
      Agent.get_and_update(__MODULE__, fn state ->
        next_result =
          case state.patch_results do
            [result | rest] -> {result, rest}
            [] -> {{:ok, %{"ok" => true}}, []}
          end

        {result, remaining_results} = next_result

        {result,
         %{
           state
           | patch_calls: [%{session_key: session_key, attrs: attrs} | state.patch_calls],
             patch_results: remaining_results
         }}
      end)
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
    start_supervised!(FakeSpacesService)
    start_supervised!(FakeChatGateway)
    start_supervised!(FakeChatClient)

    MemoryChatStore.reset!()
    FakeSpacesService.reset!()
    FakeChatGateway.reset!()
    FakeChatClient.reset!()

    original_env = %{
      spaces_service: Application.get_env(:openclaw_zalify, :spaces_service),
      chat_store: Application.get_env(:openclaw_zalify, :chat_store),
      openclaw_chat_gateway: Application.get_env(:openclaw_zalify, :openclaw_chat_gateway),
      openclaw_chat_client: Application.get_env(:openclaw_zalify, :openclaw_chat_client)
    }

    Application.put_env(:openclaw_zalify, :spaces_service, FakeSpacesService)
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

    assert {:ok, %{session: session, agent: agent, space: space}} =
             Chat.send_message("shop-chat", nil, "Hello world",
               stream_to: self(),
               stream_ref: stream_ref
             )

    assert session.workspace_id == "shop-chat"
    assert session.agent_id == "space-shop-chat"
    assert session.openclaw_session_key == "agent:space-shop-chat:web:direct:#{session.id}"
    assert agent.agent_id == "space-shop-chat"
    assert space.id == "shop-chat"

    assert_receive {:openclaw_chat_stream, ^stream_ref,
                    {:run_started, %{session_id: session_id, run_id: "run-test-1"}}}

    assert session_id == session.id

    [call] = FakeChatClient.calls()
    assert call.session_id == session.id
    assert call.message == "Hello world"
    assert call.attachments == []
    assert call.timeout_ms == 60_000
  end

  test "send_message accepts image attachments without text" do
    stream_ref = %{request_id: "req-image"}

    assert {:ok, %{session: session}} =
             Chat.send_message("shop-images", nil, "",
               stream_to: self(),
               stream_ref: stream_ref,
               attachments: [
                 %{
                   type: "image",
                   mime_type: "image/png",
                   file_name: "lobster.png",
                   content: "data:image/png;base64,QUJDRA=="
                 }
               ]
             )

    assert_receive {:openclaw_chat_stream, ^stream_ref, {:run_started, %{session_id: session_id}}}
    assert session_id == session.id

    [call] = FakeChatClient.calls()
    assert call.message == ""

    assert call.attachments == [
             %{
               type: "image",
               mime_type: "image/png",
               file_name: "lobster.png",
               content: "data:image/png;base64,QUJDRA=="
             }
           ]
  end

  test "send_message still rejects empty text when attachments are missing" do
    assert {:error, {:validation, %{message: ["can't be blank"]}}} =
             Chat.send_message("shop-empty", nil, "   ",
               stream_to: self(),
               stream_ref: %{}
             )
  end

  test "send_message applies the space runtime overrides before streaming" do
    space =
      FakeSpacesService.build_space("shop-model", %{
        model_ref: "deepseek/deepseek-chat",
        reasoning_level: "off"
      })

    FakeSpacesService.put!(
      "shop-model",
      space,
      %AgentRecord{
        workspace_id: "shop-model",
        agent_id: "space-shop-model",
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
               attrs: %{model_ref: "deepseek/deepseek-chat", reasoning_level: "off"}
             }
           ] = FakeChatGateway.patch_calls()

    assert session_key == session.openclaw_session_key
  end

  test "send_message falls back to the gateway default model when model_ref is not allowed" do
    space =
      FakeSpacesService.build_space("shop-fallback-model", %{
        model_ref: "deepseek/deepseek-chat",
        reasoning_level: "off"
      })

    FakeSpacesService.put!(
      "shop-fallback-model",
      space,
      %AgentRecord{
        workspace_id: "shop-fallback-model",
        agent_id: "space-shop-fallback-model",
        status: "active",
        runtime_mode: "shared",
        workspace_path: "/tmp/shop-fallback-model",
        display_name: "Fallback Agent",
        model_ref: "deepseek/deepseek-chat",
        memory_enabled: true
      }
    )

    FakeChatGateway.set_patch_results([
      {:error, {:request_failed, %{"code" => "INVALID_REQUEST", "message" => "model not allowed: deepseek/deepseek-chat"}}},
      {:ok, %{"ok" => true}}
    ])

    assert {:ok, %{session: session}} =
             Chat.send_message("shop-fallback-model", nil, "Use any allowed model",
               stream_to: self(),
               stream_ref: %{}
             )

    assert [
             %{
               session_key: session_key,
               attrs: %{model_ref: "deepseek/deepseek-chat", reasoning_level: "off"}
             },
             %{
               session_key: session_key,
               attrs: %{reasoning_level: "off"}
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
