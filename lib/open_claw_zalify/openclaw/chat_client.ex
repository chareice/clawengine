defmodule OpenClawZalify.OpenClaw.ChatClient do
  @moduledoc """
  Streaming OpenClaw chat client.
  """

  use WebSockex

  alias OpenClawZalify.Config

  @protocol_version 3

  @type stream_message ::
          {:run_started, map()}
          | {:chat_event, map()}
          | {:stream_error, term()}

  @callback start_stream(keyword()) :: {:ok, pid()} | {:error, term()}

  @spec start_stream(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_stream(opts) do
    gateway = Config.openclaw_gateway()

    with true <- gateway.token_present? || {:error, :missing_gateway_token} do
      state = %{
        listener: Keyword.fetch!(opts, :stream_to),
        stream_ref: Keyword.fetch!(opts, :stream_ref),
        session_id: Keyword.fetch!(opts, :session_id),
        session_key: Keyword.fetch!(opts, :session_key),
        message: Keyword.fetch!(opts, :message),
        idempotency_key: Keyword.fetch!(opts, :idempotency_key),
        timeout_ms: Keyword.get(opts, :timeout_ms, Config.openclaw_chat_timeout_ms()),
        token: gateway.token,
        version: Keyword.get(opts, :version, OpenClawZalify.version()),
        request_id: nil,
        connect_id: nil,
        connect_sent?: false,
        completed?: false,
        run_id: nil,
        timeout_ref: nil
      }

      WebSockex.start(
        Config.openclaw_gateway_ws_url(),
        __MODULE__,
        state,
        handle_initial_conn_failure: true
      )
    end
  end

  @impl true
  def handle_connect(_conn, state) do
    timeout_ref = Process.send_after(self(), :stream_timeout, state.timeout_ms)
    {:ok, %{state | timeout_ref: timeout_ref}}
  end

  @impl true
  def handle_frame({:text, raw}, state) do
    with {:ok, frame} <- Jason.decode(raw) do
      handle_incoming_frame(frame, state)
    else
      {:error, reason} ->
        notify_and_close(state, {:stream_error, {:invalid_json, reason}})
    end
  end

  @impl true
  def handle_info(:stream_timeout, %{completed?: true} = state) do
    {:ok, state}
  end

  @impl true
  def handle_info(:stream_timeout, state) do
    notify_and_close(state, {:stream_error, :timeout})
  end

  @impl true
  def handle_disconnect(%{reason: _reason}, %{completed?: true} = state) do
    {:ok, state}
  end

  @impl true
  def handle_disconnect(%{reason: reason}, state) do
    notify_listener(state, {:stream_error, {:disconnect, reason}})
    {:ok, %{state | completed?: true}}
  end

  defp handle_incoming_frame(
         %{"type" => "event", "event" => "connect.challenge"},
         %{connect_sent?: false} = state
       ) do
    connect_id = Ecto.UUID.generate()

    payload = %{
      "type" => "req",
      "id" => connect_id,
      "method" => "connect",
      "params" => %{
        "minProtocol" => @protocol_version,
        "maxProtocol" => @protocol_version,
        "client" => %{
          "id" => "gateway-client",
          "displayName" => "openclaw-zalify-chat",
          "version" => state.version,
          "platform" => "elixir",
          "mode" => "backend",
          "instanceId" => "openclaw-zalify-chat"
        },
        "caps" => [],
        "role" => "operator",
        "scopes" => ["operator.admin", "operator.read", "operator.write"],
        "auth" => %{"token" => state.token}
      }
    }

    {:reply, {:text, Jason.encode!(payload)},
     %{state | connect_id: connect_id, connect_sent?: true}}
  end

  defp handle_incoming_frame(
         %{"type" => "res", "id" => id, "ok" => true},
         %{connect_id: id} = state
       ) do
    send_chat_request(state)
  end

  defp handle_incoming_frame(
         %{"type" => "res", "id" => id, "ok" => true, "payload" => payload},
         %{request_id: id} = state
       ) do
    run_id = Map.get(payload, "runId")

    notify_listener(state, {
      :run_started,
      %{
        session_id: state.session_id,
        session_key: state.session_key,
        run_id: run_id,
        status: Map.get(payload, "status")
      }
    })

    {:ok, %{state | run_id: run_id}}
  end

  defp handle_incoming_frame(
         %{"type" => "event", "event" => "chat", "payload" => payload},
         state
       ) do
    payload_session_key = Map.get(payload, "sessionKey")
    payload_run_id = Map.get(payload, "runId")

    cond do
      payload_session_key != state.session_key ->
        {:ok, state}

      is_binary(state.run_id) and is_binary(payload_run_id) and payload_run_id != state.run_id ->
        {:ok, state}

      true ->
        event = %{
          session_id: state.session_id,
          session_key: state.session_key,
          run_id: payload_run_id || state.run_id,
          state: Map.get(payload, "state"),
          seq: Map.get(payload, "seq"),
          message: Map.get(payload, "message"),
          usage: Map.get(payload, "usage"),
          stop_reason: Map.get(payload, "stopReason"),
          error_message: Map.get(payload, "errorMessage"),
          raw: payload
        }

        notify_listener(state, {:chat_event, event})

        if Map.get(payload, "state") in ["final", "error", "aborted"] do
          close_stream(%{state | completed?: true, run_id: payload_run_id || state.run_id})
        else
          {:ok, %{state | run_id: payload_run_id || state.run_id}}
        end
    end
  end

  defp handle_incoming_frame(
         %{"type" => "res", "id" => id, "ok" => false, "error" => error},
         %{connect_id: id} = state
       ) do
    notify_and_close(state, {:stream_error, {:connect_failed, error}})
  end

  defp handle_incoming_frame(
         %{"type" => "res", "id" => id, "ok" => false, "error" => error},
         %{request_id: id} = state
       ) do
    notify_and_close(state, {:stream_error, {:request_failed, error}})
  end

  defp handle_incoming_frame(_frame, state) do
    {:ok, state}
  end

  defp send_chat_request(state) do
    request_id = Ecto.UUID.generate()

    payload = %{
      "type" => "req",
      "id" => request_id,
      "method" => "chat.send",
      "params" => %{
        "sessionKey" => state.session_key,
        "message" => state.message,
        "deliver" => false,
        "idempotencyKey" => state.idempotency_key,
        "timeoutMs" => state.timeout_ms
      }
    }

    {:reply, {:text, Jason.encode!(payload)}, %{state | request_id: request_id}}
  end

  defp notify_and_close(state, message) do
    notify_listener(state, message)
    close_stream(%{state | completed?: true})
  end

  defp close_stream(state) do
    if state.timeout_ref, do: Process.cancel_timer(state.timeout_ref)
    {:close, state}
  end

  defp notify_listener(state, message) do
    send(state.listener, {:openclaw_chat_stream, state.stream_ref, message})
  end
end
