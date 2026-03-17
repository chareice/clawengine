defmodule ClawEngine.OpenClaw.Client do
  @moduledoc false

  use WebSockex

  @protocol_version 3

  def request(opts, method, params) do
    state = %{
      caller: self(),
      completed?: false,
      connect_sent?: false,
      method: method,
      params: params,
      token: Keyword.fetch!(opts, :token),
      request_id: nil,
      connect_id: nil,
      version: Keyword.get(opts, :version, "0.1.0")
    }

    case WebSockex.start(Keyword.fetch!(opts, :url), __MODULE__, state,
           handle_initial_conn_failure: true
         ) do
      {:ok, pid} ->
        receive do
          {:openclaw_result, ^pid, result} ->
            Process.exit(pid, :normal)
            result
        after
          Keyword.get(opts, :timeout, 5_000) ->
            Process.exit(pid, :normal)
            {:error, :timeout}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_connect(_conn, state) do
    {:ok, state}
  end

  @impl true
  def handle_frame({:text, raw}, state) do
    with {:ok, frame} <- Jason.decode(raw) do
      handle_incoming_frame(frame, state)
    else
      {:error, reason} ->
        send_result(state, {:error, {:invalid_json, reason}})
        {:ok, state}
    end
  end

  @impl true
  def handle_disconnect(%{reason: reason}, state) do
    if state.completed? do
      :ok
    else
      send_result(state, {:error, {:disconnect, reason}})
    end

    {:ok, state}
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
          "displayName" => "clawengine",
          "version" => state.version,
          "platform" => "elixir",
          "mode" => "backend",
          "instanceId" => "clawengine"
        },
        "caps" => [],
        "role" => "operator",
        "scopes" => ["operator.admin"],
        "auth" => %{"token" => state.token}
      }
    }

    {:reply, {:text, Jason.encode!(payload)},
     %{state | connect_id: connect_id, connect_sent?: true}}
  end

  defp handle_incoming_frame(
         %{"type" => "res", "id" => id, "ok" => true, "payload" => _payload},
         %{connect_id: id} = state
       ) do
    request_id = Ecto.UUID.generate()

    reply =
      Jason.encode!(%{
        "type" => "req",
        "id" => request_id,
        "method" => state.method,
        "params" => state.params
      })

    {:reply, {:text, reply}, %{state | request_id: request_id}}
  end

  defp handle_incoming_frame(
         %{"type" => "res", "id" => id, "ok" => true, "payload" => payload},
         %{request_id: id} = state
       ) do
    next_state = %{state | completed?: true}
    send_result(next_state, {:ok, payload})
    {:ok, next_state}
  end

  defp handle_incoming_frame(
         %{"type" => "res", "id" => id, "ok" => false, "error" => error},
         %{connect_id: id} = state
       ) do
    next_state = %{state | completed?: true}
    send_result(next_state, {:error, {:connect_failed, error}})
    {:ok, next_state}
  end

  defp handle_incoming_frame(
         %{"type" => "res", "id" => id, "ok" => false, "error" => error},
         %{request_id: id} = state
       ) do
    next_state = %{state | completed?: true}
    send_result(next_state, {:error, {:request_failed, error}})
    {:ok, next_state}
  end

  defp handle_incoming_frame(_frame, state) do
    {:ok, state}
  end

  defp send_result(state, result) do
    send(state.caller, {:openclaw_result, self(), result})
  end
end
