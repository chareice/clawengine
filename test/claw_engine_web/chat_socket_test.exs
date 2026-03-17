defmodule ClawEngineWeb.ChatSocketTest do
  use ExUnit.Case, async: false

  alias ClawEngine.Chat.SessionRecord
  alias ClawEngineWeb.ChatSocket

  defmodule FakeChatService do
    def send_message(space_id, session_id, message, opts) do
      session =
        %SessionRecord{
          id: session_id || "session-1",
          workspace_id: space_id || "shop-ws",
          agent_id: "space-shop-ws",
          openclaw_session_key: "agent:space-shop-ws:web:direct:session-1",
          status: "active"
        }

      send(
        Keyword.fetch!(opts, :stream_to),
        {:openclaw_chat_stream, Keyword.fetch!(opts, :stream_ref),
         {:run_started,
          %{
            session_id: session.id,
            session_key: session.openclaw_session_key,
            run_id: "run-ws-1",
            status: "started"
          }}}
      )

      send(
        Keyword.fetch!(opts, :stream_to),
        {:openclaw_chat_stream, Keyword.fetch!(opts, :stream_ref),
         {:chat_event,
          %{
            session_id: session.id,
            session_key: session.openclaw_session_key,
            run_id: "run-ws-1",
            state: "final",
            seq: 1,
            message: %{
              "role" => "assistant",
              "content" => [%{"type" => "text", "text" => message}]
            },
            usage: nil,
            stop_reason: "stop",
            error_message: nil,
            raw: %{"state" => "final"}
          }}}
      )

      {:ok, %{session: session}}
    end

    def get_history(session_id, _limit) do
      {:ok,
       %{
         session: %SessionRecord{
           id: session_id,
           workspace_id: "shop-ws",
           agent_id: "space-shop-ws",
           openclaw_session_key: "agent:space-shop-ws:web:direct:#{session_id}",
           status: "active"
         },
         history: %{"messages" => [%{"role" => "assistant"}]}
       }}
    end

    def abort_run(session_id, run_id) do
      {:ok,
       %{
         session: %SessionRecord{
           id: session_id,
           workspace_id: "shop-ws",
           agent_id: "space-shop-ws",
           openclaw_session_key: "agent:space-shop-ws:web:direct:#{session_id}",
           status: "active"
         },
         result: %{"aborted" => true, "runIds" => [run_id]}
       }}
    end
  end

  setup do
    original_chat_service = Application.get_env(:claw_engine, :chat_service)
    Application.put_env(:claw_engine, :chat_service, FakeChatService)

    on_exit(fn ->
      Application.put_env(:claw_engine, :chat_service, original_chat_service)
    end)

    {:ok, state} = ChatSocket.init([])
    %{state: state}
  end

  test "responds to ping frames", %{state: state} do
    assert {:push, {:text, raw}, _next_state} =
             ChatSocket.handle_in(
               {Jason.encode!(%{"type" => "ping", "request_id" => "req-ping"}), [opcode: :text]},
               state
             )

    assert %{"type" => "pong", "request_id" => "req-ping"} = Jason.decode!(raw)
  end

  test "send_message returns session_ready and forwards streamed events", %{state: state} do
    request =
      Jason.encode!(%{
        "type" => "send_message",
        "request_id" => "req-send",
        "space_id" => "shop-ws",
        "message" => "hello over ws"
      })

    assert {:push, {:text, raw}, next_state} =
             ChatSocket.handle_in({request, [opcode: :text]}, state)

    assert %{
             "type" => "session_ready",
             "request_id" => "req-send",
             "session" => %{"space_id" => "shop-ws", "id" => "session-1"}
           } = Jason.decode!(raw)

    assert_receive started_message =
                     {:openclaw_chat_stream, %{request_id: "req-send"}, {:run_started, _payload}}

    assert {:push, {:text, started_raw}, next_state} =
             ChatSocket.handle_info(started_message, next_state)

    assert %{
             "type" => "run_started",
             "request_id" => "req-send",
             "run_id" => "run-ws-1"
           } = Jason.decode!(started_raw)

    assert_receive event_message =
                     {:openclaw_chat_stream, %{request_id: "req-send"}, {:chat_event, _payload}}

    assert {:push, {:text, event_raw}, _state} =
             ChatSocket.handle_info(event_message, next_state)

    assert %{
             "type" => "chat_event",
             "request_id" => "req-send",
             "state" => "final",
             "run_id" => "run-ws-1"
           } = Jason.decode!(event_raw)
  end

  test "get_history returns the serialized history payload", %{state: state} do
    request =
      Jason.encode!(%{
        "type" => "get_history",
        "request_id" => "req-history",
        "session_id" => "session-1"
      })

    assert {:push, {:text, raw}, _state} =
             ChatSocket.handle_in({request, [opcode: :text]}, state)

    assert %{
             "type" => "history",
             "request_id" => "req-history",
             "session" => %{"id" => "session-1"},
             "messages" => [%{"role" => "assistant"}]
           } = Jason.decode!(raw)
  end

  test "abort_run returns the abort response", %{state: state} do
    request =
      Jason.encode!(%{
        "type" => "abort_run",
        "request_id" => "req-abort",
        "session_id" => "session-1",
        "run_id" => "run-ws-1"
      })

    assert {:push, {:text, raw}, _state} =
             ChatSocket.handle_in({request, [opcode: :text]}, state)

    assert %{
             "type" => "run_aborted",
             "request_id" => "req-abort",
             "aborted" => true,
             "run_ids" => ["run-ws-1"]
           } = Jason.decode!(raw)
  end

  test "returns a validation error for unsupported frame types", %{state: state} do
    request = Jason.encode!(%{"type" => "unknown", "request_id" => "req-unknown"})

    assert {:push, {:text, raw}, _state} =
             ChatSocket.handle_in({request, [opcode: :text]}, state)

    assert %{
             "type" => "error",
             "request_id" => "req-unknown",
             "error" => "validation_error"
           } = Jason.decode!(raw)
  end
end
