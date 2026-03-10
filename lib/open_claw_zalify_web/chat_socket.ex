defmodule OpenClawZalifyWeb.ChatSocket do
  @moduledoc false

  @behaviour WebSock

  alias OpenClawZalify.Chat

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_in({raw, [opcode: :text]}, state) do
    with {:ok, payload} <- Jason.decode(raw),
         {:ok, reply, next_state} <- handle_payload(payload, state) do
      {:push, {:text, Jason.encode!(reply)}, next_state}
    else
      {:payload_error, reason, request_id} ->
        {:push, {:text, Jason.encode!(error_frame(reason, request_id))}, state}

      {:error, reason} ->
        {:push, {:text, Jason.encode!(error_frame(reason, nil))}, state}
    end
  end

  @impl true
  def handle_info({:openclaw_chat_stream, stream_ref, {:run_started, payload}}, state) do
    frame =
      payload
      |> Map.put(:type, "run_started")
      |> maybe_put_request_id(stream_ref)
      |> stringify_keys()

    {:push, {:text, Jason.encode!(frame)}, state}
  end

  def handle_info({:openclaw_chat_stream, stream_ref, {:chat_event, payload}}, state) do
    frame =
      payload
      |> Map.put(:type, "chat_event")
      |> maybe_put_request_id(stream_ref)
      |> stringify_keys()

    {:push, {:text, Jason.encode!(frame)}, state}
  end

  def handle_info({:openclaw_chat_stream, stream_ref, {:stream_error, reason}}, state) do
    request_id =
      case stream_ref do
        %{request_id: request_id} -> request_id
        _other -> nil
      end

    {:push, {:text, Jason.encode!(error_frame(reason, request_id))}, state}
  end

  def handle_info(_message, state) do
    {:ok, state}
  end

  defp handle_payload(%{"type" => "ping"} = payload, state) do
    {:ok, base_frame("pong", payload), state}
  end

  defp handle_payload(%{"type" => "send_message"} = payload, state) do
    request_id = Map.get(payload, "request_id")
    stream_ref = %{request_id: request_id}
    space_id = Map.get(payload, "space_id") || Map.get(payload, "workspace_id")

    case chat_service().send_message(
           space_id,
           Map.get(payload, "session_id"),
           Map.get(payload, "message", ""),
           stream_to: self(),
           stream_ref: stream_ref,
           idempotency_key:
             normalize_text(Map.get(payload, "idempotency_key")) || Ecto.UUID.generate(),
           timeout_ms: normalize_timeout_ms(Map.get(payload, "timeout_ms"))
         ) do
      {:ok, %{session: session}} ->
        {:ok,
         %{
           "type" => "session_ready",
           "request_id" => request_id,
           "session" => Chat.serialize_session(session)
         }, state}

      {:error, reason} ->
        {:ok, error_frame(reason, request_id), state}
    end
  end

  defp handle_payload(%{"type" => "get_history"} = payload, state) do
    request_id = Map.get(payload, "request_id")
    limit = normalize_limit(Map.get(payload, "limit"))

    case chat_service().get_history(Map.get(payload, "session_id", ""), limit) do
      {:ok, %{session: session, history: history}} ->
        reply = %{
          "type" => "history",
          "request_id" => request_id,
          "session" => Chat.serialize_session(session),
          "messages" => Map.get(history, "messages", [])
        }

        {:ok, reply, state}

      {:error, reason} ->
        {:ok, error_frame(reason, request_id), state}
    end
  end

  defp handle_payload(%{"type" => "abort_run"} = payload, state) do
    request_id = Map.get(payload, "request_id")

    case chat_service().abort_run(Map.get(payload, "session_id", ""), Map.get(payload, "run_id")) do
      {:ok, %{session: session, result: result}} ->
        reply = %{
          "type" => "run_aborted",
          "request_id" => request_id,
          "session" => Chat.serialize_session(session),
          "aborted" => Map.get(result, "aborted"),
          "run_ids" => Map.get(result, "runIds", [])
        }

        {:ok, reply, state}

      {:error, reason} ->
        {:ok, error_frame(reason, request_id), state}
    end
  end

  defp handle_payload(%{"type" => type} = payload, _state) when is_binary(type) do
    {:payload_error, {:validation, %{type: ["is not supported"]}}, Map.get(payload, "request_id")}
  end

  defp handle_payload(payload, _state) do
    request_id =
      case payload do
        %{} -> Map.get(payload, "request_id")
        _other -> nil
      end

    {:payload_error, {:validation, %{payload: ["must be a JSON object with a type"]}}, request_id}
  end

  defp error_frame({:validation, details}, request_id) do
    %{
      "type" => "error",
      "request_id" => request_id,
      "error" => "validation_error",
      "details" => details
    }
  end

  defp error_frame({:not_found, :session}, request_id) do
    %{
      "type" => "error",
      "request_id" => request_id,
      "error" => "not_found",
      "details" => %{"session" => ["was not found"]}
    }
  end

  defp error_frame({:not_found, :space}, request_id) do
    %{
      "type" => "error",
      "request_id" => request_id,
      "error" => "not_found",
      "details" => %{"space" => ["was not found in the instance config"]}
    }
  end

  defp error_frame({:connect_failed, reason}, request_id) do
    %{
      "type" => "error",
      "request_id" => request_id,
      "error" => "openclaw_connect_failed",
      "details" => reason
    }
  end

  defp error_frame({:request_failed, reason}, request_id) do
    %{
      "type" => "error",
      "request_id" => request_id,
      "error" => "openclaw_request_failed",
      "details" => reason
    }
  end

  defp error_frame(reason, request_id) do
    %{
      "type" => "error",
      "request_id" => request_id,
      "error" => "internal_error",
      "details" => inspect(reason)
    }
  end

  defp base_frame(type, payload) do
    %{
      "type" => type,
      "request_id" => Map.get(payload, "request_id")
    }
  end

  defp maybe_put_request_id(map, %{request_id: request_id}) when is_binary(request_id) do
    Map.put(map, :request_id, request_id)
  end

  defp maybe_put_request_id(map, _stream_ref), do: map

  defp stringify_keys(map) do
    Enum.into(map, %{}, fn {key, value} ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          other -> other
        end

      normalized_value =
        cond do
          is_map(value) -> stringify_keys(value)
          is_list(value) -> Enum.map(value, &stringify_nested/1)
          true -> value
        end

      {normalized_key, normalized_value}
    end)
  end

  defp stringify_nested(value) when is_map(value), do: stringify_keys(value)
  defp stringify_nested(value), do: value

  defp normalize_timeout_ms(value) when is_integer(value) and value > 0, do: value
  defp normalize_timeout_ms(_value), do: OpenClawZalify.Config.openclaw_chat_timeout_ms()

  defp normalize_limit(value) when is_integer(value) and value > 0, do: value
  defp normalize_limit(_value), do: 50

  defp normalize_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_text(_value), do: nil

  defp chat_service do
    Application.get_env(:openclaw_zalify, :chat_service, OpenClawZalify.Chat)
  end
end
