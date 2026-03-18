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
         %{"type" => "event", "event" => "connect.challenge", "payload" => %{"nonce" => nonce}},
         %{connect_sent?: false} = state
       ) do
    connect_id = Ecto.UUID.generate()

    device_params = build_device_params(state, nonce, "gateway-client", "backend", ["operator.admin"])

    params = %{
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
      "auth" => build_auth_params(state)
    }

    params = if device_params, do: Map.put(params, "device", device_params), else: params

    payload = %{
      "type" => "req",
      "id" => connect_id,
      "method" => "connect",
      "params" => params
    }

    {:reply, {:text, Jason.encode!(payload)},
     %{state | connect_id: connect_id, connect_sent?: true}}
  end

  # Fallback for connect.challenge without nonce (backward compat)
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
        "auth" => build_auth_params(state)
      }
    }

    {:reply, {:text, Jason.encode!(payload)},
     %{state | connect_id: connect_id, connect_sent?: true}}
  end

  defp handle_incoming_frame(
         %{"type" => "res", "id" => id, "ok" => true, "payload" => payload},
         %{connect_id: id} = state
       ) do
    # Save device token if provided
    if auth = payload["auth"] do
      if device_token = auth["deviceToken"] do
        ClawEngine.DeviceTokenStore.save_token("operator", device_token, auth["scopes"] || [])
      end
    end

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

  defp build_device_params(state, nonce, client_id, client_mode, scopes) do
    case ClawEngine.DeviceIdentity.ensure_identity() do
      {:ok, identity} ->
        signed_at = System.system_time(:millisecond)

        sign_params = %{
          device_id: identity.device_id,
          client_id: client_id,
          client_mode: client_mode,
          role: "operator",
          scopes: scopes,
          signed_at_ms: signed_at,
          token: state.token,
          nonce: nonce,
          platform: "elixir",
          device_family: nil
        }

        payload_str = ClawEngine.DeviceIdentity.build_payload_v3(sign_params)
        signature = ClawEngine.DeviceIdentity.sign(identity.private_key_raw, payload_str)

        %{
          "id" => identity.device_id,
          "publicKey" => ClawEngine.DeviceIdentity.public_key_base64url(identity.public_key_raw),
          "signature" => signature,
          "signedAt" => signed_at,
          "nonce" => nonce
        }

      {:error, _} ->
        nil
    end
  end

  defp build_auth_params(state) do
    auth = %{"token" => state.token}

    case ClawEngine.DeviceTokenStore.get_token("operator") do
      {:ok, token} -> Map.put(auth, "deviceToken", token)
      _ -> auth
    end
  end

  defp send_result(state, result) do
    send(state.caller, {:openclaw_result, self(), result})
  end
end
