defmodule OpenClawZalify.OpenClaw.ChatGateway do
  @moduledoc """
  Request/response RPC helper for OpenClaw chat session operations.
  """

  alias OpenClawZalify.Config
  alias OpenClawZalify.OpenClaw.Client

  @callback patch_session(String.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback chat_history(String.t(), pos_integer()) :: {:ok, map()} | {:error, term()}
  @callback abort_chat(String.t(), String.t() | nil) :: {:ok, map()} | {:error, term()}

  @spec patch_session(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def patch_session(session_key, attrs) when is_binary(session_key) and is_map(attrs) do
    params =
      attrs
      |> Enum.reduce(%{"key" => session_key}, fn
        {:model_ref, value}, acc when is_binary(value) ->
          Map.put(acc, "model", value)

        {:reasoning_level, value}, acc when is_binary(value) ->
          Map.put(acc, "reasoningLevel", value)

        {_key, nil}, acc ->
          acc

        {_key, _value}, acc ->
          acc
      end)

    request("sessions.patch", params)
  end

  @spec chat_history(String.t(), pos_integer()) :: {:ok, map()} | {:error, term()}
  def chat_history(session_key, limit) do
    request("chat.history", %{
      "sessionKey" => session_key,
      "limit" => limit
    })
  end

  @spec abort_chat(String.t(), String.t() | nil) :: {:ok, map()} | {:error, term()}
  def abort_chat(session_key, run_id) do
    params =
      %{"sessionKey" => session_key}
      |> maybe_put("runId", run_id)

    request("chat.abort", params)
  end

  defp request(method, params) do
    gateway = Config.openclaw_gateway()

    with true <- gateway.token_present? || {:error, :missing_gateway_token},
         {:ok, payload} <-
           Client.request(
             [
               url: Config.openclaw_gateway_ws_url(),
               token: gateway.token,
               timeout: Config.openclaw_admin_timeout_ms(),
               version: OpenClawZalify.version()
             ],
             method,
             params
           ) do
      {:ok, payload}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
